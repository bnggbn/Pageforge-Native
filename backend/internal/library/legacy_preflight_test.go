package library

import (
	"github.com/bnggbn/Pageforge-Native/backend/internal/fault"
	"os"
	"path/filepath"
	"testing"
)

func TestLegacyCommitPreflightPreservesReadableHead(t *testing.T) {
	s := testStore(t)
	s.config.Storage.RecordMiB = 1
	s.config.Storage.HistoryMiB = 1
	id, _, err := s.Import("legacy.txt", []byte(benchmarkObjectText(100000)))
	if err != nil {
		t.Fatal(err)
	}
	b, err := s.LoadHistory(id)
	if err != nil {
		t.Fatal(err)
	}
	file := filepath.Join(s.root, "books", id, "manifest.json")
	for i := 0; i < 20; i++ {
		before, err := os.ReadFile(file)
		if err != nil {
			t.Fatal(err)
		}
		head := b.Revisions[len(b.Revisions)-1]
		next, err := s.CommitReader(id, Commit{ExpectedHead: head.ID, Kind: "edit", Content: head.Content + "追加。"})
		if err == nil {
			b, err = s.LoadHistory(id)
			if err != nil {
				t.Fatal(err)
			}
			_ = next
			continue
		}
		if code, _ := fault.CodeOf(err); code != fault.LimitExceeded {
			t.Fatal(err)
		}
		after, err := os.ReadFile(file)
		if err != nil || string(after) != string(before) {
			t.Fatal("failed preflight changed manifest", err)
		}
		s.cache = nil
		loaded, err := s.LoadReader(id)
		if err != nil || loaded.Revisions[len(loaded.Revisions)-1].ID != head.ID {
			t.Fatal("old legacy head locked", err)
		}
		return
	}
	t.Fatal("fixture never reached the aggregate history budget")
}
