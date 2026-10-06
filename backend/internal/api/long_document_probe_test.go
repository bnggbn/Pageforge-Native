package api

import (
	"encoding/json"
	"fmt"
	"io/fs"
	"math/rand/v2"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
	"unicode/utf16"
	"unicode/utf8"

	"github.com/bnggbn/Pageforge-Native/backend/internal/compare"
	"github.com/bnggbn/Pageforge-Native/backend/internal/config"
	"github.com/bnggbn/Pageforge-Native/backend/internal/library"
	"github.com/bnggbn/Pageforge-Native/backend/internal/model"
	"github.com/bnggbn/Pageforge-Native/backend/internal/vax"
)

type documentProbeSample struct {
	Operation string  `json:"operation"`
	Ms        float64 `json:"ms"`
	Allocated uint64  `json:"allocatedBytes"`
	Mallocs   uint64  `json:"mallocs"`
	Error     string  `json:"error,omitempty"`
}

type documentProbeResult struct {
	Characters       int                   `json:"characters"`
	UTF8Bytes        int                   `json:"utf8Bytes"`
	UTF16Units       int                   `json:"utf16Units"`
	InitialRevisions int                   `json:"initialRevisions"`
	DefaultAccepted  bool                  `json:"defaultAccepted"`
	CacheEligible    bool                  `json:"cacheEligible"`
	HistoryBytes     int64                 `json:"historyBytes"`
	ReaderBytes      int                   `json:"readerBytes"`
	FinalDiskBytes   int64                 `json:"finalDiskBytes"`
	Samples          []documentProbeSample `json:"samples"`
}

// Explicit opt-in: ordinary CI never builds multi-hundred-MiB synthetic libraries.
// Measurements are wall time and cumulative Go allocations, not peak memory or RSS.
func TestLargeDocumentProbe(t *testing.T) {
	if os.Getenv("PAGEFORGE_LONG_DOCUMENT_PROBE") != "1" {
		t.Skip("set PAGEFORGE_LONG_DOCUMENT_PROBE=1 for synthetic capacity probe")
	}
	t.Logf("environment: %s %s/%s CPUs=%d", runtime.Version(), runtime.GOOS, runtime.GOARCH, runtime.NumCPU())
	cases := []struct{ characters, revisions int }{
		{100_000, 10}, {1_000_000, 10}, {3_000_000, 1},
		{3_000_000, 10}, {3_000_000, 40}, {5_000_000, 1}, {5_000_000, 10},
	}
	for _, tc := range cases {
		t.Run(fmt.Sprintf("chars_%d_versions_%d", tc.characters, tc.revisions), func(t *testing.T) {
			probeDocument(t, tc.characters, tc.revisions)
		})
	}
}

func probeDocument(t *testing.T, characters, revisions int) {
	t.Helper()
	content := probeText(characters)
	if utf8.RuneCountInString(content) != characters {
		t.Fatal("generator did not produce the requested rune count")
	}
	result := documentProbeResult{
		Characters: characters, UTF8Bytes: len(content),
		UTF16Units: len(utf16.Encode([]rune(content))), InitialRevisions: revisions,
	}
	defaults, err := config.Load(filepath.Join("..", "..", ".."))
	if err != nil {
		t.Fatal(err)
	}
	defaults.Paths.LibraryRoot = t.TempDir()
	defaultStore := openProbeStore(t, defaults)
	result.Samples = append(result.Samples, measureDocumentProbe("default_import", func() error {
		_, _, err := defaultStore.Import("synthetic.txt", []byte(content))
		result.DefaultAccepted = err == nil
		return err
	}))
	if result.DefaultAccepted != (len(content) <= defaults.Limits.TextMiB*1024*1024) {
		t.Fatal("default capacity guard disagrees with input bytes")
	}
	if err := defaultStore.Close(); err != nil {
		t.Fatal(err)
	}

	// Experiment-only overrides. No product configuration or user library is changed.
	c := defaults
	c.Storage.RevisionFormat = "legacy"
	c.Paths.LibraryRoot = t.TempDir()
	c.Limits.TextMiB, c.Limits.DocumentMiB, c.Limits.RequestMiB = 32, 32, 64
	c.Storage.HistoryMiB = 512
	store := openProbeStore(t, c)
	defer func() { _ = store.Close() }()
	var id string
	result.Samples = append(result.Samples, measureDocumentProbe("raised_import", func() error {
		id, _, err = store.Import("synthetic.txt", []byte(content))
		return err
	}))
	if err != nil {
		t.Fatal(err)
	}
	book, err := store.Load(id)
	if err != nil {
		t.Fatal(err)
	}
	// Build valid immutable fixtures directly, avoiding O(revisions²) commit setup.
	// Measured edit/note saves below use the public Commit path.
	root := filepath.Join(c.Paths.LibraryRoot, "books", id)
	manifestBytes, err := os.ReadFile(filepath.Join(root, "manifest.json"))
	if err != nil {
		t.Fatal(err)
	}
	var manifest model.Manifest
	if err := json.Unmarshal(manifestBytes, &manifest); err != nil {
		t.Fatal(err)
	}
	last := book.Revisions[0]
	for i := 1; i < revisions; i++ {
		next, err := vax.Create(book.Document, &last, "edit", content+fmt.Sprintf("\nrevision %d", i), nil, nil)
		if err != nil {
			t.Fatal(err)
		}
		writeProbeJSON(t, filepath.Join(root, "versions", next.ID+".json"), next)
		manifest.RevisionIDs = append(manifest.RevisionIDs, next.ID)
		last = next
	}
	writeProbeJSON(t, filepath.Join(root, "manifest.json"), manifest)
	original, err := os.Stat(filepath.Join(root, "original.txt"))
	if err != nil {
		t.Fatal(err)
	}
	result.HistoryBytes = original.Size() + probeDiskBytes(t, filepath.Join(root, "versions"))
	result.CacheEligible = result.HistoryBytes <= int64(c.Storage.VerifiedCacheMiB)*1024*1024

	for i := 0; i < 3; i++ {
		if err := store.Close(); err != nil {
			t.Fatal(err)
		}
		store = openProbeStore(t, c) // clear the application cache, not the Windows file cache
		result.Samples = append(result.Samples, measureDocumentProbe("cold_load", func() error {
			book, err = store.Load(id)
			return err
		}))
		if err != nil || len(book.Revisions) != revisions {
			t.Fatalf("cold load: revisions=%d err=%v", len(book.Revisions), err)
		}
		result.Samples = append(result.Samples, measureDocumentProbe("repeat_load", func() error {
			book, err = store.Load(id)
			return err
		}))
		if err != nil {
			t.Fatal(err)
		}
	}

	app := New(store, c, func() {})
	handler := app.Handler()
	for i := 0; i < 3; i++ {
		result.Samples = append(result.Samples, measureDocumentProbe("reader_handler", func() error {
			request := httptest.NewRequest("GET", "http://127.0.0.1:12345/v1/books/"+id+"?view=reader", nil)
			request.Header.Set("Authorization", "Bearer "+app.Token)
			response := httptest.NewRecorder()
			handler.ServeHTTP(response, request)
			if response.Code != 200 {
				return fmt.Errorf("reader status %d", response.Code)
			}
			result.ReaderBytes = response.Body.Len()
			return nil
		}))
	}

	head := book.Revisions[len(book.Revisions)-1]
	var token *string
	for i := 0; i < 3; i++ {
		draft := model.Draft{
			ID: "30000000-0000-4000-8000-000000000001", DocumentID: id, BaseRevisionID: head.ID,
		}
		changed := head.Content + fmt.Sprintf("\ndraft %d", i)
		draft.Content = &changed
		result.Samples = append(result.Samples, measureDocumentProbe("full_draft_save", func() error {
			saved, err := store.SaveDraft(id, draft, token)
			if err == nil {
				token = &saved.Version
			}
			return err
		}))
	}
	result.Samples = append(result.Samples, measureDocumentProbe("default_diff", func() error {
		_, err := compare.Text(content, content+"改", defaults.Diff.MaxCharacters, defaults.Diff.TimeoutMs)
		return err
	}))
	for i := 0; i < 3; i++ {
		result.Samples = append(result.Samples, measureDocumentProbe("edit_commit", func() error {
			book, err = store.Commit(id, library.Commit{
				ExpectedHead: head.ID, Kind: "edit", Content: head.Content + "改",
			})
			if err == nil {
				head = book.Revisions[len(book.Revisions)-1]
			}
			return err
		}))
	}
	result.Samples = append(result.Samples, measureDocumentProbe("note_commit", func() error {
		_, err := store.Commit(id, library.Commit{
			ExpectedHead: head.ID, Kind: "note", Content: head.Content, Notes: []model.Note{{
				ID: vax.UUID(), Body: "Synthetic clue", Quote: "test", Location: "probe", CreatedAt: vax.Now(),
			}},
		})
		return err
	}))
	result.FinalDiskBytes = probeDiskBytes(t, root)
	for _, sample := range result.Samples {
		if sample.Error != "" && sample.Operation != "default_import" && sample.Operation != "default_diff" {
			t.Fatalf("unexpected probe error %s: %s", sample.Operation, sample.Error)
		}
	}
	encoded, err := json.Marshal(result)
	if err != nil {
		t.Fatal(err)
	}
	t.Log("PAGEFORGE_PROBE " + string(encoded))
}

func measureDocumentProbe(operation string, run func() error) documentProbeSample {
	runtime.GC()
	var before, after runtime.MemStats
	runtime.ReadMemStats(&before)
	start := time.Now()
	err := run()
	elapsed := time.Since(start)
	runtime.ReadMemStats(&after)
	sample := documentProbeSample{
		Operation: operation, Ms: float64(elapsed.Microseconds()) / 1000,
		Allocated: after.TotalAlloc - before.TotalAlloc, Mallocs: after.Mallocs - before.Mallocs,
	}
	if err != nil {
		sample.Error = err.Error()
	}
	return sample
}

func openProbeStore(t *testing.T, c config.Config) *library.Store {
	t.Helper()
	store, err := library.Open(c)
	if err != nil {
		t.Fatal(err)
	}
	return store
}

func writeProbeJSON(t *testing.T, file string, value any) {
	t.Helper()
	data, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(file, data, 0600); err != nil {
		t.Fatal(err)
	}
}

func probeDiskBytes(t *testing.T, root string) int64 {
	t.Helper()
	var total int64
	err := filepath.WalkDir(root, func(file string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if !entry.IsDir() {
			info, err := entry.Info()
			if err != nil {
				return err
			}
			total += info.Size()
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	return total
}

func probeText(characters int) string {
	pool := []rune("文件閱讀段落版本筆記線索測試創作保存歷史中文 abcdefghijklmnopqrstuvwxyz0123456789🌿✨")
	random := rand.New(rand.NewPCG(42, 99))
	var text strings.Builder
	text.Grow(characters * 3)
	for i := 0; i < characters; i++ {
		if i%160 == 158 || i%160 == 159 {
			text.WriteByte('\n')
		} else {
			text.WriteRune(pool[random.IntN(len(pool))])
		}
	}
	return text.String()
}
