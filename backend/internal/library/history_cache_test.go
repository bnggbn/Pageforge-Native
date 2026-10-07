package library

import (
	"github.com/bnggbn/Pageforge-Native/backend/internal/fault"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestVerifiedCacheRejectsTamperingWithRestoredTimestamp(t *testing.T) {
	for _, original := range []bool{false, true} {
		t.Run(map[bool]string{false: "snapshot", true: "original"}[original], func(t *testing.T) {
			s := testStore(t)
			id, _, err := s.Import("cache.txt", []byte("original text"))
			if err != nil {
				t.Fatal(err)
			}
			b, err := s.LoadHistory(id)
			if err != nil {
				t.Fatal(err)
			}
			firstCache := s.cache
			b, err = s.LoadHistory(id)
			if err != nil || s.cache != firstCache {
				t.Fatalf("warm read: %v", err)
			}
			file := filepath.Join(s.root, "books", id, "versions", b.Revisions[0].ID+".json")
			if original {
				file = filepath.Join(s.root, "books", id, "original.txt")
			}
			stat, _ := os.Stat(file)
			data, _ := os.ReadFile(file)
			data = []byte(strings.Replace(string(data), "original text", "tampered text", 1))
			if err = os.WriteFile(file, data, 0600); err != nil {
				t.Fatal(err)
			}
			if err = os.Chtimes(file, stat.ModTime(), stat.ModTime()); err != nil {
				t.Fatal(err)
			}
			if _, err = s.LoadHistory(id); err == nil {
				t.Fatal("modified bytes bypassed VAX verification")
			}
		})
	}
}

func TestVerifiedCacheDoesNotAliasReturnedSnapshots(t *testing.T) {
	s := testStore(t)
	id, _, _ := s.Import("cache.txt", []byte("keep"))
	first, err := s.LoadHistory(id)
	if err != nil {
		t.Fatal(err)
	}
	first.Revisions[0].Content = "caller mutation"
	warm, err := s.LoadHistory(id)
	if err != nil || warm.Revisions[0].Content != "keep" {
		t.Fatal("cache aliases caller")
	}
	warm.Revisions[0].Content = "second caller mutation"
	again, err := s.LoadHistory(id)
	if err != nil || again.Revisions[0].Content != "keep" {
		t.Fatal("warm cache aliases caller")
	}
	s.config.Storage.VerifiedCacheMiB = 0
	s.cache = nil
	if _, err = s.LoadHistory(id); err != nil || s.cache != nil {
		t.Fatal("disabled cache retained history")
	}
}

func TestBoundedRecordsAndCumulativeHistory(t *testing.T) {
	s := testStore(t)
	id, _, _ := s.Import("budget.txt", []byte("keep"))
	b, err := s.LoadHistory(id)
	if err != nil {
		t.Fatal(err)
	}
	file := filepath.Join(s.root, "books", id, "versions", b.Revisions[0].ID+".json")
	s.config.Storage.RecordMiB = 1
	stream, err := os.OpenFile(file, os.O_WRONLY, 0600)
	if err != nil {
		t.Fatal(err)
	}
	err = stream.Truncate(1024*1024 + 1)
	stream.Close()
	if err != nil {
		t.Fatal(err)
	}
	if _, err = s.LoadHistory(id); err == nil {
		t.Fatal("oversized snapshot accepted")
	}
	s.config.Storage.RecordMiB = 2
	s.config.Storage.HistoryMiB = 1
	_, err = s.LoadHistory(id)
	if errorCode, ok := fault.CodeOf(err); !ok || errorCode != fault.LimitExceeded {
		t.Fatalf("aggregate budget: %v", err)
	}
}

func TestSyncDeduplicatesWithinBatchAndOnRepeat(t *testing.T) {
	s := testStore(t)
	folder := filepath.Join(s.root, "collection")
	for name, text := range map[string]string{"a.txt": "same", "b.txt": "same", "c.md": "different"} {
		if err := os.WriteFile(filepath.Join(folder, name), []byte(text), 0600); err != nil {
			t.Fatal(err)
		}
	}
	count, err := s.SyncCollection()
	if err != nil || count != 2 {
		t.Fatalf("initial sync %d %v", count, err)
	}
	count, err = s.SyncCollection()
	if err != nil || count != 0 {
		t.Fatalf("repeat sync %d %v", count, err)
	}
}
