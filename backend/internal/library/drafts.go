package library

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/bnggbn/Pageforge-Native/backend/internal/model"
	"github.com/bnggbn/Pageforge-Native/backend/internal/vax"
)

func (s *Store) Drafts(id string) ([]model.Draft, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if _, err := s.manifest(id); err != nil {
		return nil, err
	}
	return s.drafts(id)
}
func (s *Store) drafts(id string) ([]model.Draft, error) {
	folder, err := s.safe("books", id, "drafts")
	if err != nil {
		return nil, err
	}
	entries, err := os.ReadDir(folder)
	if errors.Is(err, os.ErrNotExist) {
		return []model.Draft{}, nil
	}
	if err != nil {
		return nil, err
	}
	result := []model.Draft{}
	count := 0
	var total int64
	for _, entry := range entries {
		if entry.IsDir() || !uuid.MatchString(strings.TrimSuffix(entry.Name(), ".json")) || !strings.HasSuffix(entry.Name(), ".json") {
			continue
		}
		file, err := s.safe("books", id, "drafts", entry.Name())
		if err != nil {
			return nil, err
		}
		count++
		if count > s.config.Limits.WorkingCopyCount {
			return nil, fmt.Errorf("draft count exceeds the configured limit")
		}
		limit := int64(s.config.Storage.RecordMiB) * 1024 * 1024
		remaining := int64(s.config.Storage.HistoryMiB)*1024*1024 - total
		if remaining < limit {
			limit = remaining
		}
		data, err := readBounded(file, limit)
		if err != nil {
			return nil, err
		}
		total += int64(len(data))
		var copy model.Draft
		if err = json.Unmarshal(data, &copy); err != nil {
			return nil, err
		}
		if copy.DocumentID != id || copy.ID+".json" != entry.Name() {
			return nil, fmt.Errorf("invalid draft source")
		}
		if copy.BranchID == "" {
			result = append(result, copy)
		}
	}
	sort.Slice(result, func(i, j int) bool { return result[i].UpdatedAt > result[j].UpdatedAt })
	return result, nil
}
func (s *Store) SaveDraft(id string, copy model.Draft, expectedVersion *string) (model.Draft, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	m, err := s.manifest(id)
	if err != nil {
		return copy, err
	}
	validBase := false
	for _, revision := range m.RevisionIDs {
		if revision == copy.BaseRevisionID {
			validBase = true
		}
	}
	if copy.DocumentID != id || !uuid.MatchString(copy.ID) || !validBase || copy.BranchID != "" ||
		len([]rune(copy.Body)) > s.config.Limits.NoteCharacters || len([]rune(copy.Quote)) > s.config.Limits.QuoteCharacters ||
		len([]rune(copy.Location)) > s.config.Limits.LocationCharacters || (copy.Content != nil && len(*copy.Content) > s.config.Limits.TextMiB*1024*1024) {
		return copy, fmt.Errorf("invalid draft source, content or size")
	}
	file, err := s.safe("books", id, "drafts", copy.ID+".json")
	if err != nil {
		return copy, err
	}
	var old model.Draft
	err = s.readJSON(file, &old)
	if err == nil {
		if expectedVersion == nil || old.Version != *expectedVersion {
			return copy, ErrConflict
		}
	} else {
		if !errors.Is(err, os.ErrNotExist) {
			return copy, err
		}
		if expectedVersion != nil {
			return copy, ErrConflict
		}
		folder := filepath.Dir(file)
		if err = os.MkdirAll(folder, 0700); err != nil {
			return copy, err
		}
		entries, err := os.ReadDir(folder)
		if err != nil {
			return copy, err
		}
		count := 0
		for _, entry := range entries {
			if strings.HasSuffix(entry.Name(), ".json") {
				count++
			}
		}
		if count >= s.config.Limits.WorkingCopyCount {
			return copy, fmt.Errorf("draft count has reached the configured limit")
		}
	}
	copy.Version = vax.UUID()
	copy.UpdatedAt = vax.Now()
	return copy, atomicJSON(file, copy)
}
func (s *Store) RemoveDraft(id, draftID, version string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if !uuid.MatchString(draftID) {
		return fmt.Errorf("invalid draft ID")
	}
	if _, err := s.manifest(id); err != nil {
		return err
	}
	file, err := s.safe("books", id, "drafts", draftID+".json")
	if err != nil {
		return err
	}
	var copy model.Draft
	if err = s.readJSON(file, &copy); err != nil {
		return err
	}
	if copy.Version != version {
		return ErrConflict
	}
	return os.Remove(file)
}
