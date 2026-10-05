package library

import (
	"encoding/json"
	"fmt"
	"io"
	"math"
	"os"

	"github.com/bnggbn/Pageforge-Native/backend/internal/model"
	"github.com/bnggbn/Pageforge-Native/backend/internal/vax"
)

type SaveEvidence struct {
	Wall             model.EvidenceWall `json:"wall"`
	ExpectedRevision string             `json:"expectedRevision"`
	ExpectedHead     string             `json:"expectedHead"`
}

func (s *Store) evidence(id string) (model.EvidenceWall, error) {
	wall := model.EvidenceWall{SchemaVersion: 1, Cards: []model.EvidenceCard{}, Edges: []model.EvidenceEdge{}}
	file, err := s.safe("books", id, "evidence-wall.json")
	if err != nil {
		return wall, err
	}
	stream, err := os.Open(file)
	if os.IsNotExist(err) {
		return wall, nil
	}
	if err != nil {
		return wall, err
	}
	defer stream.Close()
	data, err := io.ReadAll(io.LimitReader(stream, 1024*1024+1))
	if err != nil {
		return wall, err
	}
	if len(data) > 1024*1024 {
		return wall, fmt.Errorf("線索牆超過容量")
	}
	if err = json.Unmarshal(data, &wall); err != nil {
		return wall, err
	}
	return wall, s.validateEvidence(wall, nil)
}
func (s *Store) LoadEvidence(id string) (model.EvidenceWall, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if _, err := s.manifest(id); err != nil {
		return model.EvidenceWall{}, err
	}
	return s.evidence(id)
}
func (s *Store) SaveEvidence(id string, input SaveEvidence) (model.EvidenceWall, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	manifest, err := s.manifest(id)
	if err != nil {
		return input.Wall, err
	}
	head := manifest.RevisionIDs[len(manifest.RevisionIDs)-1]
	if head != input.ExpectedHead {
		return input.Wall, ErrConflict
	}
	current, err := s.evidence(id)
	if err != nil {
		return input.Wall, err
	}
	if current.Revision != input.ExpectedRevision {
		return input.Wall, ErrConflict
	}
	// Layout writes do not rehash the whole document chain or rewrite its versions.
	file, err := s.safe("books", id, "versions", head+".json")
	if err != nil {
		return input.Wall, err
	}
	var revision model.Revision
	if err = readJSON(file, &revision); err != nil {
		return input.Wall, err
	}
	notes := map[string]bool{}
	for _, note := range revision.Notes {
		notes[note.ID] = true
	}
	if err = s.validateEvidence(input.Wall, notes); err != nil {
		return input.Wall, err
	}
	wall := input.Wall
	wall.Revision = vax.UUID()
	wall.UpdatedAt = vax.Now()
	file, err = s.safe("books", id, "evidence-wall.json")
	if err != nil {
		return wall, err
	}
	return wall, atomicJSON(file, wall)
}
func (s *Store) validateEvidence(w model.EvidenceWall, notes map[string]bool) error {
	c := s.config.EvidenceWall
	if w.Cards == nil || w.Edges == nil || w.SchemaVersion != 1 || len(w.Cards) > c.MaxCards || len(w.Edges) > c.MaxEdges ||
		(w.Revision != "" && !uuid.MatchString(w.Revision)) {
		return fmt.Errorf("線索牆格式或容量無效")
	}
	cards := map[string]bool{}
	for _, card := range w.Cards {
		if !uuid.MatchString(card.NoteID) || cards[card.NoteID] || (notes != nil && !notes[card.NoteID]) ||
			math.IsNaN(card.X) || math.IsInf(card.X, 0) || math.IsNaN(card.Y) || math.IsInf(card.Y, 0) ||
			card.X < 0 || card.Y < 0 || card.X > float64(c.CanvasWidth-280) || card.Y > float64(c.CanvasHeight-240) {
			return fmt.Errorf("線索卡片位置或筆記來源無效")
		}
		cards[card.NoteID] = true
	}
	edges, pairs := map[string]bool{}, map[string]bool{}
	for _, edge := range w.Edges {
		a, b := edge.From, edge.To
		if a > b {
			a, b = b, a
		}
		pair := a + ":" + b
		if !uuid.MatchString(edge.ID) || edges[edge.ID] || pairs[pair] || edge.From == edge.To ||
			!cards[edge.From] || !cards[edge.To] || len([]rune(edge.Label)) > 200 {
			return fmt.Errorf("紅線端點或標籤無效")
		}
		edges[edge.ID] = true
		pairs[pair] = true
	}
	return nil
}
