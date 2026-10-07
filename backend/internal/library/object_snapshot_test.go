package library

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/bnggbn/Pageforge-Native/backend/internal/fault"
	"github.com/bnggbn/Pageforge-Native/backend/internal/model"
	"github.com/bnggbn/Pageforge-Native/backend/internal/vax"
)

// Scaled versions of distinct-edit and accumulating-note walls: ordinary CI
// proves capacity semantics without allocating hundreds of MiB per run.
func TestReaderSnapshotDoesNotRetainExpandedHistory(t *testing.T) {
	for _, workload := range []string{"distinct_edits", "accumulating_notes"} {
		t.Run(workload, func(t *testing.T) {
			s := testStore(t)
			s.config.Storage.RevisionFormat = objectRevisionFormat
			s.config.Storage.HistoryMiB = 4
			s.config.Storage.VerifiedCacheMiB = 1
			source := benchmarkObjectText(100000)
			id, _, err := s.Import("bounded.txt", []byte(source))
			if err != nil {
				t.Fatal(err)
			}
			b, err := s.Load(id)
			if err != nil {
				t.Fatal(err)
			}
			original := b.Revisions[0]
			previous := original
			folder := filepath.Join(s.root, "books", id)
			m, err := s.manifest(id)
			if err != nil {
				t.Fatal(err)
			}
			for i := 0; i < 48; i++ {
				kind, text, notes := "edit", source, previous.Notes
				if workload == "distinct_edits" {
					at := (i * 1709) % len(source)
					// UTF-8 boundary; each revision changes a different prefix length.
					for at > 0 && source[at]&0xc0 == 0x80 {
						at--
					}
					text = source[:at] + "changed sentence.\n" + source[at:]
				} else {
					kind = "note"
					notes = append(append([]model.Note{}, notes...), model.Note{
						ID: vax.UUID(), Body: strings.Repeat("想法", 100), Quote: strings.Repeat("引文", 100), Location: "全文筆記", CreatedAt: vax.Now(),
					})
				}
				next, err := vax.Create(m.Document, &previous, kind, text, notes, nil)
				if err != nil {
					t.Fatal(err)
				}
				if err = s.writeRevision(folder, m.RevisionStorage, next); err != nil {
					t.Fatal(err)
				}
				m.RevisionIDs = append(m.RevisionIDs, next.ID)
				m.Document.UpdatedAt = next.CreatedAt
				previous = next
			}
			if err = atomicJSON(filepath.Join(folder, "manifest.json"), m); err != nil {
				t.Fatal(err)
			}
			s.cache = nil
			// The compatibility/full audit endpoint still has its aggregate expansion cap.
			_, err = s.LoadHistory(id)
			if code, _ := fault.CodeOf(err); code != fault.LimitExceeded {
				t.Fatalf("full audit should exceed cap: %v", err)
			}
			for _, cold := range []bool{true, false} {
				if cold {
					s.cache = nil
				}
				b, err = s.Load(id)
				if err != nil {
					t.Fatal("bounded reader", cold, err)
				}
				if len(b.Revisions) != 1 || b.RevisionCount != 49 || len(b.History) != 49 || b.Revisions[0].Content != previous.Content || len(b.Revisions[0].Notes) != len(previous.Notes) {
					t.Fatal("snapshot/history mismatch")
				}
				if s.cache == nil || s.cache.snapshotID != previous.ID || s.cache.retainedBytes > 1024*1024 {
					t.Fatal("current-only cache not retained")
				}
			}
			if workload == "accumulating_notes" {
				b.Revisions[0].Notes[0].Body = "caller mutation"
				warm, err := s.Load(id)
				if err != nil || warm.Revisions[0].Notes[0].Body == "caller mutation" {
					t.Fatal("cache slice alias", err)
				}
			}
			old, err := s.LoadRevision(id, original.ID)
			if err != nil || old.Content != source || len(old.Notes) != 0 {
				t.Fatal("lazy old snapshot", err)
			}
			if s.cache == nil || s.cache.snapshotID != previous.ID {
				t.Fatal("historical read evicted the verified head")
			}
			restored, err := s.Commit(id, Commit{ExpectedHead: previous.ID, Kind: "restore", RestoredFrom: &original.ID})
			if err != nil || len(restored.Revisions) != 1 || restored.RevisionCount != 50 || restored.Revisions[0].Content != source || len(restored.Revisions[0].Notes) != 0 {
				t.Fatal("restore after full-audit wall", err)
			}
			// Editing and saving remain available after the old aggregate wall.
			edited, err := s.Commit(id, Commit{ExpectedHead: restored.Revisions[0].ID, Kind: "edit", Content: source + "追加。"})
			if err != nil || edited.RevisionCount != 51 {
				t.Fatal("edit after full-audit wall", err)
			}
		})
	}
}

func TestReaderSnapshotChecksUnselectedHistoryBytesOnWarmLoad(t *testing.T) {
	s, id, b := objectFixture(t)
	first := b.Revisions[0]
	updated, err := s.Commit(id, Commit{ExpectedHead: first.ID, Kind: "edit", Content: "new head"})
	if err != nil || updated.RevisionCount != 2 {
		t.Fatal(err)
	}
	// Warm cache must cover original-version dependencies, not only the head root.
	file := filepath.Join(s.root, "books", id, "versions", first.ID+".json")
	data, err := os.ReadFile(file)
	if err != nil {
		t.Fatal(err)
	}
	data[len(data)/2] ^= 1
	if err = os.WriteFile(file, data, 0600); err != nil {
		t.Fatal(err)
	}
	if _, err = s.Load(id); err == nil {
		t.Fatal("unselected version corruption ignored")
	}
}

func TestDefaultSnapshotContractAcrossStorageFormats(t *testing.T) {
	for _, format := range []string{"legacy", objectRevisionFormat} {
		t.Run(format, func(t *testing.T) {
			s := testStore(t)
			s.config.Storage.RevisionFormat = format
			id, _, err := s.Import("contract.txt", []byte("original"))
			if err != nil {
				t.Fatal(err)
			}
			b, err := s.Load(id)
			if err != nil || len(b.Revisions) != 1 || b.RevisionCount != 1 {
				t.Fatal("default Load", err)
			}
			old := b.Revisions[0].ID
			for i := 0; i < 2; i++ {
				b, err = s.Commit(id, Commit{ExpectedHead: b.Revisions[0].ID, Kind: "edit", Content: b.Revisions[0].Content + " changed"})
				if err != nil || len(b.Revisions) != 1 || b.RevisionCount != i+2 || len(b.History) != i+2 {
					t.Fatal("default Commit must return one snapshot", err)
				}
			}
			history, err := s.LoadHistory(id)
			if err != nil || len(history.Revisions) != 3 {
				t.Fatal("explicit history", err)
			}
			selected, err := s.LoadRevision(id, old)
			if err != nil || selected.Content != "original" {
				t.Fatal("historical selection", err)
			}
		})
	}
}

func TestReaderCacheIncludesCurrentChapterProjection(t *testing.T) {
	s, id, b := objectFixture(t)
	s.config.Storage.VerifiedCacheMiB = 1
	m, err := s.manifest(id)
	if err != nil {
		t.Fatal(err)
	}
	projection := strings.Repeat("view", 512*1024)
	m.Document.Sections = []model.Section{{Title: "chapter", Text: projection}}
	original := b.Revisions[0]
	first, err := vax.Create(m.Document, nil, "import", original.Content, original.Notes, nil)
	if err != nil {
		t.Fatal(err)
	}
	folder := filepath.Join(s.root, "books", id)
	if err = s.writeRevision(folder, m.RevisionStorage, first); err != nil {
		t.Fatal(err)
	}
	m.RevisionIDs = []string{first.ID}
	if err = atomicJSON(filepath.Join(folder, "manifest.json"), m); err != nil {
		t.Fatal(err)
	}
	s.cache = nil
	loaded, err := s.Load(id)
	if err != nil || loaded.Sections[0].Text != projection {
		t.Fatal(err)
	}
	if s.cache != nil {
		t.Fatal("large current chapter projection ignored by cache capacity")
	}
	s.config.Storage.VerifiedCacheMiB = 4
	loaded, err = s.Load(id)
	if err != nil || s.cache == nil {
		t.Fatal("within-capacity projection was not cached", err)
	}
	loaded.Sections[0].Text = "caller mutation"
	warm, err := s.Load(id)
	if err != nil || warm.Sections[0].Text != projection {
		t.Fatal("projection cache alias", err)
	}
}
