package library

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/bnggbn/Pageforge-Native/backend/internal/config"
	"github.com/bnggbn/Pageforge-Native/backend/internal/model"
)

func testStore(t *testing.T) *Store {
	t.Helper()
	c, err := config.Load(filepath.Join("..", "..", ".."))
	if err != nil {
		t.Fatal(err)
	}
	c.Paths.LibraryRoot = t.TempDir()
	s, err := Open(c)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { s.Close() })
	return s
}
func TestImportCommitConflictProgressAndDrafts(t *testing.T) {
	s := testStore(t)
	id, duplicate, err := s.Import("測試.md", []byte("# 初稿🌿\n"))
	if err != nil || duplicate {
		t.Fatalf("import: %v", err)
	}
	same, duplicate, err := s.Import("改名.md", []byte("# 初稿🌿\n"))
	if err != nil || !duplicate || same != id {
		t.Fatal("duplicate source was not detected")
	}
	b, err := s.Load(id)
	if err != nil {
		t.Fatal(err)
	}
	head := b.Revisions[0]
	if err = s.SaveProgress(id, model.Position{RevisionID: head.ID, Block: "native-scroll", Ratio: .5, Percentage: 50}); err != nil {
		t.Fatal(err)
	}
	before, err := os.ReadFile(filepath.Join(s.root, "books", id, "manifest.json"))
	if err != nil {
		t.Fatal(err)
	}
	copy := model.Draft{ID: "30000000-0000-4000-8000-000000000001", DocumentID: id, BaseRevisionID: head.ID, Body: "一個想法", Location: "全文筆記"}
	saved, err := s.SaveDraft(id, copy, nil)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = s.SaveDraft(id, copy, nil); !errors.Is(err, ErrConflict) {
		t.Fatalf("expected draft conflict: %v", err)
	}
	drafts, err := s.Drafts(id)
	if err != nil || len(drafts) != 1 || drafts[0].Content != nil {
		t.Fatal("reference draft did not survive reload")
	}
	updated, err := s.Commit(id, Commit{ExpectedHead: head.ID, Kind: "edit", Content: "# 修改✨\n"})
	if err != nil {
		t.Fatal(err)
	}
	if updated.Progress != nil {
		t.Fatal("old text progress survived an edit")
	}
	if _, err = s.Commit(id, Commit{ExpectedHead: head.ID, Kind: "edit", Content: "過期"}); !errors.Is(err, ErrConflict) {
		t.Fatal("stale head accepted")
	}
	if err = s.SaveProgress(id, model.Position{RevisionID: head.ID}); !errors.Is(err, ErrConflict) {
		t.Fatal("stale progress accepted")
	}
	restored, err := s.Commit(id, Commit{ExpectedHead: updated.Revisions[1].ID, Kind: "restore", RestoredFrom: &head.ID})
	if err != nil {
		t.Fatal(err)
	}
	if restored.Revisions[2].Content != head.Content || len(restored.Revisions) != 3 {
		t.Fatal("restore discarded history")
	}
	if err = s.RemoveDraft(id, saved.ID, saved.Version); err != nil {
		t.Fatal(err)
	}
	after, _ := os.ReadFile(filepath.Join(s.root, "books", id, "manifest.json"))
	if string(before) == string(after) {
		t.Fatal("head was not committed")
	}
	revisionsPath := filepath.Join(s.root, "books", id, "versions", restored.Revisions[1].ID+".json")
	var revision model.Revision
	readJSON(revisionsPath, &revision)
	revision.Content = "tampered"
	atomicJSON(revisionsPath, revision)
	if _, err = s.Load(id); err == nil {
		t.Fatal("tampered history loaded")
	}
}
func TestReadExistingWebLibraryAndKeepUnknownBranches(t *testing.T) {
	s := testStore(t)
	bytes, err := os.ReadFile(filepath.Join("..", "vax", "testdata", "web-history.json"))
	if err != nil {
		t.Fatal(err)
	}
	var fixture struct {
		Document  model.Document   `json:"document"`
		Source    string           `json:"source"`
		Revisions []model.Revision `json:"revisions"`
	}
	if err = json.Unmarshal(bytes, &fixture); err != nil {
		t.Fatal(err)
	}
	root := filepath.Join(s.root, "books", fixture.Document.ID)
	os.MkdirAll(filepath.Join(root, "versions"), 0700)
	os.WriteFile(filepath.Join(root, "original.md"), []byte(fixture.Source), 0600)
	m := model.Manifest{Document: fixture.Document, OriginalFile: "original.md", OriginalType: "text/markdown"}
	for _, revision := range fixture.Revisions {
		m.RevisionIDs = append(m.RevisionIDs, revision.ID)
		atomicJSON(filepath.Join(root, "versions", revision.ID+".json"), revision)
	}
	atomicJSON(filepath.Join(root, "manifest.json"), m)
	branchPath := filepath.Join(root, "branches", "30000000-0000-4000-8000-000000000001")
	if err = os.MkdirAll(branchPath, 0700); err != nil {
		t.Fatal(err)
	}
	sentinel := filepath.Join(branchPath, "manifest.json")
	if err = os.WriteFile(sentinel, []byte(`{"retained":"existing sandbox"}`), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err = s.Load(fixture.Document.ID); err != nil {
		t.Fatal(err)
	}
	_, err = s.Commit(fixture.Document.ID, Commit{ExpectedHead: fixture.Revisions[len(fixture.Revisions)-1].ID,
		Kind: "edit", Content: "Go 修改，沙盒仍保留"})
	if err != nil {
		t.Fatal(err)
	}
	retained, err := os.ReadFile(sentinel)
	if err != nil || string(retained) != `{"retained":"existing sandbox"}` {
		t.Fatal("existing sandbox changed")
	}
	if _, err = Open(s.config); err == nil {
		t.Fatal("second writer opened same library")
	}
}
func TestRejectInvalidSourceAndPath(t *testing.T) {
	s := testStore(t)
	for _, source := range [][]byte{{0xff}, {0}, {' ', ' '}} {
		if _, _, err := s.Import("bad.txt", source); err == nil {
			t.Fatal("invalid text imported")
		}
	}
	if _, _, err := s.Import("../escape.md", []byte("hello")); err == nil {
		t.Fatal("path traversal accepted")
	}
	if _, err := s.Load("../escape"); err == nil {
		t.Fatal("invalid document path accepted")
	}
}
