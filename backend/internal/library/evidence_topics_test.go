package library

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/bnggbn/Pageforge-Native/backend/internal/model"
	"github.com/bnggbn/Pageforge-Native/backend/internal/vax"
)

func TestEvidenceV1MigrationBackupsAndTopics(t *testing.T) {
	s, book, old := evidenceFixture(t)
	old.Revision = vax.UUID()
	file := filepath.Join(s.root, "books", book.ID, "evidence-wall.json")
	if err := atomicJSON(file, old); err != nil {
		t.Fatal(err)
	}
	before, _ := os.ReadFile(file)
	loaded, err := s.LoadEvidence(book.ID)
	if err != nil || loaded.SchemaVersion != 2 || loaded.ActiveTopic != model.AllEvidenceTopic || len(loaded.Topics) != 1 || loaded.Topics[0].Edges[0].Label != "相互印證" {
		t.Fatal("migration did not preserve layout", err)
	}
	after, _ := os.ReadFile(file)
	if string(before) != string(after) {
		t.Fatal("read mutated original layout")
	}
	customID := vax.UUID()
	loaded.Topics = append(loaded.Topics, model.EvidenceTopic{ID: customID, Name: "待查證", Cards: []model.EvidenceCard{{NoteID: old.Cards[0].NoteID, X: 810, Y: 300}}, Edges: []model.EvidenceEdge{}})
	loaded.ActiveTopic = customID
	head := book.Revisions[len(book.Revisions)-1].ID
	saved, err := s.SaveEvidence(book.ID, SaveEvidence{Wall: loaded, ExpectedRevision: old.Revision, ExpectedHead: head})
	if err != nil {
		t.Fatal(err)
	}
	backup, err := os.ReadFile(filepath.Join(s.root, "books", book.ID, "evidence-wall.v1.backup.json"))
	if err != nil || string(backup) != string(before) {
		t.Fatal("exact original backup missing", err)
	}
	next, err := s.LoadEvidence(book.ID)
	if err != nil || next.ActiveTopic != customID || next.Topics[0].Cards[0].X != 40 || next.Topics[1].Cards[0].X != 810 {
		t.Fatal("topic layouts leaked", err)
	}
	next.Topics[1].Cards[0].X = 920
	if _, err = s.SaveEvidence(book.ID, SaveEvidence{Wall: next, ExpectedRevision: saved.Revision, ExpectedHead: head}); err != nil {
		t.Fatal(err)
	}
	backupAgain, _ := os.ReadFile(filepath.Join(s.root, "books", book.ID, "evidence-wall.v1.backup.json"))
	if string(backupAgain) != string(before) {
		t.Fatal("migration backup was overwritten")
	}
	if _, err = s.Load(book.ID); err != nil {
		t.Fatal("VAX changed", err)
	}
}

func TestEvidenceTopicValidation(t *testing.T) {
	s, book, old := evidenceFixture(t)
	base := migrateEvidence(old)
	custom := model.EvidenceTopic{ID: vax.UUID(), Name: "人物關係", Cards: []model.EvidenceCard{old.Cards[0]}, Edges: []model.EvidenceEdge{}}
	base.Topics = append(base.Topics, custom)
	base.ActiveTopic = custom.ID
	cases := []func(*model.EvidenceWall){
		func(w *model.EvidenceWall) { w.Topics[1].Name = "全部線索" },
		func(w *model.EvidenceWall) { w.Topics[1].Name = " " },
		func(w *model.EvidenceWall) { w.Topics[1].ID = w.Topics[0].ID },
		func(w *model.EvidenceWall) { w.ActiveTopic = vax.UUID() },
		func(w *model.EvidenceWall) { w.Topics = w.Topics[1:] },
		func(w *model.EvidenceWall) { w.Topics[0].Name = "改名" },
		func(w *model.EvidenceWall) { w.Topics[1].Edges = []model.EvidenceEdge{old.Edges[0]} },
		func(w *model.EvidenceWall) { w.Topics[1].Cards = nil },
	}
	for i, mutate := range cases {
		data, _ := json.Marshal(base)
		var copy model.EvidenceWall
		json.Unmarshal(data, &copy)
		mutate(&copy)
		if _, err := s.SaveEvidence(book.ID, SaveEvidence{Wall: copy, ExpectedHead: book.Revisions[len(book.Revisions)-1].ID}); err == nil {
			t.Fatalf("invalid topic case %d accepted", i)
		}
	}
}
