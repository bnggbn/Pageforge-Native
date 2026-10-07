package library

import (
	"encoding/json"
	"math"
	"strings"
	"unicode/utf8"

	"github.com/bnggbn/Pageforge-Native/backend/internal/fault"
	"github.com/bnggbn/Pageforge-Native/backend/internal/model"
	"github.com/bnggbn/Pageforge-Native/backend/internal/vax"
)

type Commit struct {
	ExpectedHead string       `json:"expectedHead"`
	Kind         string       `json:"kind"`
	Content      string       `json:"content"`
	Notes        []model.Note `json:"notes"`
	RestoredFrom *string      `json:"restoredFrom"`
}

func (s *Store) Commit(id string, input Commit) (model.Book, error) {
	return s.commit(id, input, true)
}

// CommitHistory preserves the old full-history return contract for audit callers.
func (s *Store) CommitHistory(id string, input Commit) (model.Book, error) {
	return s.commit(id, input, false)
}
func (s *Store) CommitReader(id string, input Commit) (model.Book, error) {
	return s.commit(id, input, true)
}
func (s *Store) commit(id string, input Commit, reader bool) (model.Book, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var b model.Book
	var err error
	if reader {
		b, err = s.readSnapshot(id, "")
	} else {
		b, err = s.readBook(id)
	}
	if err != nil {
		return b, err
	}
	head := b.Revisions[len(b.Revisions)-1]
	if head.ID != input.ExpectedHead {
		return b, ErrConflict
	}
	count := len(b.Revisions)
	if b.RevisionCount != 0 {
		count = b.RevisionCount
	}
	if count >= s.config.Limits.RevisionCount {
		return b, fault.New(fault.LimitExceeded, "版本數已達設定上限")
	}
	if input.Kind != "edit" && input.Kind != "note" && input.Kind != "restore" {
		return b, fault.New(fault.InvalidRequest, "此階段支援 edit／note／restore")
	}
	content := input.Content
	notes := input.Notes
	if input.Kind == "restore" {
		found := false
		if input.RestoredFrom != nil {
			if reader && b.RevisionCount != 0 {
				old, readErr := s.readSnapshot(id, *input.RestoredFrom)
				if readErr != nil {
					return b, readErr
				}
				content, notes = old.Revisions[0].Content, old.Revisions[0].Notes
				found = true
			}
			for _, r := range b.Revisions {
				if r.ID == *input.RestoredFrom {
					content = r.Content
					notes = r.Notes
					found = true
				}
			}
		}
		if !found {
			return b, fault.New(fault.InvalidRequest, "還原來源不在此主線")
		}
	} else if input.RestoredFrom != nil {
		return b, fault.New(fault.InvalidRequest, "此事件不可設定還原來源")
	}
	editable := b.Format == "markdown" || b.Format == "text"
	if len(content) > s.config.Limits.TextMiB*1024*1024 {
		return b, fault.New(fault.LimitExceeded, "文字超過設定容量")
	}
	if !utf8.ValidString(content) ||
		(editable && (strings.TrimSpace(content) == "" || strings.ContainsRune(content, 0))) || (!editable && content != "") {
		return b, fault.New(fault.InvalidRequest, "文字格式或容量無效")
	}
	if input.Kind == "note" {
		content = head.Content
	} else if input.Kind == "edit" {
		notes = head.Notes
	}
	if err = s.validateNotes(notes); err != nil {
		return b, err
	}
	r, err := vax.Create(b.Document, &head, input.Kind, content, notes, input.RestoredFrom)
	if err != nil {
		return b, err
	}
	m, err := s.manifest(id)
	if err != nil {
		return b, err
	}
	if m.RevisionIDs[len(m.RevisionIDs)-1] != input.ExpectedHead {
		return b, ErrConflict
	}
	versionFolder, err := s.safe("books", id)
	if err != nil {
		return b, err
	}
	if err = s.writeRevision(versionFolder, m.RevisionStorage, r); err != nil {
		return b, err
	}
	m.RevisionIDs = append(m.RevisionIDs, r.ID)
	m.Document.UpdatedAt = r.CreatedAt
	if head.Content != content {
		m.Progress = nil
		m.ProgressEpoch = &r.ID
		b.Progress = nil
	}
	var candidate *model.Book
	if m.RevisionStorage == objectRevisionFormat {
		var validated model.Book
		var validateErr error
		if reader {
			validated, validateErr = s.readObjectHistory(m, versionFolder, true, r.ID)
		} else {
			validated, validateErr = s.readObjectBook(m)
		}
		if validateErr != nil {
			return b, validateErr
		}
		candidate = &validated
	}
	if m.RevisionStorage != objectRevisionFormat {
		validated, validateErr := s.readLegacyBook(m)
		if validateErr != nil {
			return b, validateErr
		}
		if reader {
			validated, validateErr = projectLegacySnapshot(validated, r.ID)
			if validateErr != nil {
				return b, validateErr
			}
		}
		candidate = &validated
	}
	manifest, err := s.safe("books", id, "manifest.json")
	if err != nil {
		return b, err
	}
	if err = atomicJSON(manifest, m); err != nil {
		return b, err
	}
	b.Document = m.Document
	if candidate != nil {
		b = *candidate
	} else {
		b.Revisions = append(b.Revisions, r)
	}
	return b, nil
}
func (s *Store) validateNotes(notes []model.Note) error {
	encoded, err := json.Marshal(notes)
	if err != nil || len(encoded) > s.config.Limits.SnapshotNotesMiB*1024*1024 {
		return fault.New(fault.LimitExceeded, "筆記快照超過設定容量")
	}
	seen := map[string]bool{}
	for _, n := range notes {
		if !uuid.MatchString(n.ID) || seen[n.ID] || strings.TrimSpace(n.Body) == "" ||
			len([]rune(n.Body)) > s.config.Limits.NoteCharacters || len([]rune(n.Quote)) > s.config.Limits.QuoteCharacters ||
			len([]rune(n.Location)) > s.config.Limits.LocationCharacters {
			return fault.New(fault.InvalidRequest, "筆記內容或 ID 無效")
		}
		seen[n.ID] = true
	}
	return nil
}
func (s *Store) SaveProgress(id string, p model.Position) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	m, err := s.manifest(id)
	if err != nil {
		return err
	}
	if m.RevisionIDs[len(m.RevisionIDs)-1] != p.RevisionID {
		return ErrConflict
	}
	if p.Section < 0 || math.IsNaN(p.Percentage) || math.IsInf(p.Percentage, 0) || math.IsNaN(p.Ratio) ||
		math.IsInf(p.Ratio, 0) || p.Ratio < 0 || p.Ratio > 1 || p.Percentage < 0 || p.Percentage > 100 || len(p.Block) > 300 {
		return fault.New(fault.InvalidRequest, "閱讀位置無效")
	}
	p.Epoch = m.ProgressEpoch
	p.UpdatedAt = vax.Now()
	file, err := s.safe("books", id, "progress.json")
	if err != nil {
		return err
	}
	return atomicJSON(file, p)
}
