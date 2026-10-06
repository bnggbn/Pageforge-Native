package library

import (
	"encoding/json"
	"fmt"
	"io"
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
		return migrateEvidence(wall), nil
	}
	if err != nil {
		return wall, err
	}
	defer stream.Close()
	data, err := io.ReadAll(io.LimitReader(stream, int64(s.config.EvidenceWall.LayoutMiB)*1024*1024+1))
	if err != nil {
		return wall, err
	}
	if len(data) > s.config.EvidenceWall.LayoutMiB*1024*1024 {
		return wall, fmt.Errorf("線索牆超過容量")
	}
	wall = model.EvidenceWall{}
	if err = json.Unmarshal(data, &wall); err != nil {
		return wall, err
	}
	if err = s.validateEvidence(wall, nil); err != nil {
		return wall, err
	}
	return migrateEvidence(wall), nil
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
	currentNotes, err := s.revisionNotes(manifest, head)
	if err != nil {
		return input.Wall, err
	}
	notes := map[string]bool{}
	for _, note := range currentNotes {
		notes[note.ID] = true
	}
	if err = s.validateEvidence(input.Wall, notes); err != nil {
		return input.Wall, err
	}
	wall := migrateEvidence(input.Wall)
	wall.Revision = vax.UUID()
	wall.UpdatedAt = vax.Now()
	file, err := s.safe("books", id, "evidence-wall.json")
	if err != nil {
		return wall, err
	}
	encoded, err := json.Marshal(wall)
	if err != nil || len(encoded) > s.config.EvidenceWall.LayoutMiB*1024*1024 {
		return wall, fmt.Errorf("線索牆超過容量")
	}
	if err = s.backupEvidenceV1(id, file); err != nil {
		return wall, err
	}
	return wall, atomicJSON(file, wall)
}
