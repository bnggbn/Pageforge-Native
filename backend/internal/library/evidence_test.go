package library

import (
	"errors"
	"github.com/bnggbn/Pageforge-Native/backend/internal/model"
	"github.com/bnggbn/Pageforge-Native/backend/internal/vax"
	"math"
	"os"
	"path/filepath"
	"testing"
)

func evidenceFixture(t *testing.T) (*Store, model.Book, model.EvidenceWall) {
	t.Helper()
	s := testStore(t)
	id, _, err := s.Import("線索.md", []byte("# 線索\n\n第一段。\n\n第二段。"))
	if err != nil {
		t.Fatal(err)
	}
	book, _ := s.LoadHistory(id)
	notes := []model.Note{{ID: vax.UUID(), Body: "第一個線索", Quote: "第一段。", Location: "pf:p1:來源", CreatedAt: vax.Now()}, {ID: vax.UUID(), Body: "第二個線索", Quote: "第二段。", Location: "全文筆記", CreatedAt: vax.Now()}}
	book, err = s.CommitHistory(id, Commit{ExpectedHead: book.Revisions[0].ID, Kind: "note", Content: book.Revisions[0].Content, Notes: notes})
	if err != nil {
		t.Fatal(err)
	}
	wall := model.EvidenceWall{SchemaVersion: 1, Cards: []model.EvidenceCard{{NoteID: notes[0].ID, X: 40, Y: 40}, {NoteID: notes[1].ID, X: 360, Y: 40}}, Edges: []model.EvidenceEdge{{ID: vax.UUID(), From: notes[0].ID, To: notes[1].ID, Label: "相互印證"}}}
	return s, book, wall
}
func TestEvidencePersistenceAndVersionIsolation(t *testing.T) {
	s, book, wall := evidenceFixture(t)
	head := book.Revisions[len(book.Revisions)-1]
	folder := filepath.Join(s.root, "books", book.ID)
	manifest, _ := os.ReadFile(filepath.Join(folder, "manifest.json"))
	original, _ := os.ReadFile(filepath.Join(folder, "original.md"))
	version, _ := os.ReadFile(filepath.Join(folder, "versions", head.ID+".json"))
	empty, err := s.LoadEvidence(book.ID)
	if err != nil || empty.Revision != "" || len(empty.Cards) != 0 {
		t.Fatal("missing wall did not default", err)
	}
	saved, err := s.SaveEvidence(book.ID, SaveEvidence{Wall: wall, ExpectedHead: head.ID})
	if err != nil {
		t.Fatal(err)
	}
	loaded, err := s.LoadEvidence(book.ID)
	if err != nil || loaded.Revision != saved.Revision || loaded.Topics[0].Edges[0].Label != "相互印證" {
		t.Fatal("layout did not survive load", err)
	}
	if _, err = s.SaveEvidence(book.ID, SaveEvidence{Wall: wall, ExpectedHead: head.ID}); !errors.Is(err, ErrConflict) {
		t.Fatal("stale layout token accepted", err)
	}
	for name, before := range map[string][]byte{"manifest.json": manifest, "original.md": original, filepath.Join("versions", head.ID+".json"): version} {
		after, _ := os.ReadFile(filepath.Join(folder, name))
		if string(before) != string(after) {
			t.Fatal("layout changed immutable data", name)
		}
	}
	updated, err := s.CommitHistory(book.ID, Commit{ExpectedHead: head.ID, Kind: "note", Content: head.Content, Notes: head.Notes[:1]})
	if err != nil {
		t.Fatal(err)
	}
	if _, err = s.SaveEvidence(book.ID, SaveEvidence{Wall: wall, ExpectedRevision: saved.Revision, ExpectedHead: head.ID}); !errors.Is(err, ErrConflict) {
		t.Fatal("stale document head accepted", err)
	}
	if _, err = s.SaveEvidence(book.ID, SaveEvidence{Wall: wall, ExpectedRevision: saved.Revision, ExpectedHead: updated.Revisions[len(updated.Revisions)-1].ID}); err == nil {
		t.Fatal("removed note accepted as endpoint")
	}
	if _, err = s.LoadHistory(book.ID); err != nil {
		t.Fatal("VAX history changed", err)
	}
}
func TestEvidenceValidation(t *testing.T) {
	s, book, wall := evidenceFixture(t)
	head := book.Revisions[len(book.Revisions)-1].ID
	cases := []func(*model.EvidenceWall){
		func(w *model.EvidenceWall) { w.SchemaVersion = 2 },
		func(w *model.EvidenceWall) { w.Cards[0].X = math.NaN() },
		func(w *model.EvidenceWall) { w.Cards[0].Y = -1 },
		func(w *model.EvidenceWall) { w.Cards[0].X = 999999 },
		func(w *model.EvidenceWall) { w.Cards[0].NoteID = vax.UUID() },
		func(w *model.EvidenceWall) { w.Edges[0].To = w.Edges[0].From },
		func(w *model.EvidenceWall) { w.Edges[0].To = vax.UUID() },
		func(w *model.EvidenceWall) { w.Edges = append(w.Edges, w.Edges[0]) },
	}
	for i, mutate := range cases {
		copy := wall
		copy.Cards = append([]model.EvidenceCard{}, wall.Cards...)
		copy.Edges = append([]model.EvidenceEdge{}, wall.Edges...)
		mutate(&copy)
		if _, err := s.SaveEvidence(book.ID, SaveEvidence{Wall: copy, ExpectedHead: head}); err == nil {
			t.Fatalf("invalid case %d accepted", i)
		}
	}
	if _, err := s.LoadEvidence("../private"); err == nil {
		t.Fatal("invalid path accepted")
	}
}
