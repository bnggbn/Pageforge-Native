package library

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/bnggbn/Pageforge-Native/backend/internal/fault"
)

func TestLegacyCommitRejectsOversizedRecordBeforePublication(t *testing.T) {
	s := testStore(t)
	s.config.Storage.RecordMiB = 1
	s.config.Storage.VerifiedCacheMiB = 0
	id, _, err := s.Import("limit.txt", []byte("Original text."))
	if err != nil {
		t.Fatal(err)
	}
	book, err := s.Load(id)
	if err != nil {
		t.Fatal(err)
	}
	folder := filepath.Join(s.root, "books", id)
	before, err := os.ReadFile(filepath.Join(folder, "manifest.json"))
	if err != nil {
		t.Fatal(err)
	}
	records, err := os.ReadDir(filepath.Join(folder, "versions"))
	if err != nil {
		t.Fatal(err)
	}
	_, err = s.Commit(id, Commit{ExpectedHead: book.Revisions[0].ID, Kind: "edit", Content: strings.Repeat("文", 400000)})
	if code, _ := fault.CodeOf(err); code != fault.LimitExceeded {
		t.Fatal(err)
	}
	after, err := os.ReadFile(filepath.Join(folder, "manifest.json"))
	if err != nil || string(after) != string(before) {
		t.Fatal("oversized record moved head", err)
	}
	next, err := os.ReadDir(filepath.Join(folder, "versions"))
	if err != nil || len(next) != len(records) {
		t.Fatal("oversized record was written", err)
	}
	s.cache = nil
	if _, err = s.Load(id); err != nil {
		t.Fatal(err)
	}
}

func TestLegacyCommitReturnMatchesColdReader(t *testing.T) {
	for _, audit := range []bool{false, true} {
		t.Run(map[bool]string{false: "reader", true: "audit"}[audit], func(t *testing.T) {
			s := testStore(t)
			s.config.Storage.VerifiedCacheMiB = 0
			id, _, err := s.Import("unicode.txt", []byte("First paragraph.\r\n\r\nSecond paragraph."))
			if err != nil {
				t.Fatal(err)
			}
			book, err := s.Load(id)
			if err != nil {
				t.Fatal(err)
			}
			input := Commit{ExpectedHead: book.Revisions[0].ID, Kind: "edit", Content: "文😀\r\n\r\nSecond paragraph."}
			var saved = book
			if audit {
				saved, err = s.CommitHistory(id, input)
			} else {
				saved, err = s.Commit(id, input)
			}
			if err != nil {
				t.Fatal(err)
			}
			if audit && len(saved.Revisions) != 2 || !audit && (len(saved.Revisions) != 1 || saved.RevisionCount != 2) {
				t.Fatal("wrong return contract")
			}
			s.cache = nil
			cold, err := s.Load(id)
			head := saved.Revisions[len(saved.Revisions)-1]
			if err != nil || cold.Revisions[0].ID != head.ID || cold.Revisions[0].Content != input.Content {
				t.Fatal("published head differs from commit response", err)
			}
		})
	}
}
