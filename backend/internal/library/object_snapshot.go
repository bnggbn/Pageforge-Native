package library

import (
	"encoding/json"
	"github.com/bnggbn/Pageforge-Native/backend/internal/content"
	"github.com/bnggbn/Pageforge-Native/backend/internal/fault"
	"github.com/bnggbn/Pageforge-Native/backend/internal/model"
	"github.com/bnggbn/Pageforge-Native/backend/internal/vax"
)

// Reader snapshots share the immutable wire format with full audit loads.
// History remains metadata; only the requested snapshot is materialized.
func (s *Store) objectSnapshot(b model.Book, m model.Manifest, records []objectRevision, session *content.Session,
	source []byte, consumed, budget int64, key, metaKey, snapshotID string, allowCache bool) (model.Book, error) {
	verifier, err := vax.NewVerifier(b.Document, vax.Hash(source))
	if err != nil {
		return b, fault.Ensure(fault.StorageCorrupt, "VAX 來源驗證失敗", err)
	}
	textLimit := int64(s.config.Limits.TextMiB) * 1024 * 1024
	notesLimit := int64(s.config.Limits.SnapshotNotesMiB) * 1024 * 1024
	textHashes, noteHashes := map[string]string{}, map[string]string{}
	b.History = make([]model.RevisionSummary, 0, len(records))
	for _, record := range records {
		// Physical dependencies and one expanded snapshot are separately bounded.
		// Decoding/canonicalizing notes needs temporary buffers, not retained history arrays.
		if record.ContentRoot.Bytes+record.NotesRoot.Bytes*8 > budget-consumed-session.Bytes {
			return b, fault.New(fault.LimitExceeded, "單一版本還原超過容量限制")
		}
		textHash, found := textHashes[record.ContentRoot.Hash]
		if !found {
			textHash, err = session.TextHash(record.ContentRoot, textLimit)
			if err != nil {
				return b, fault.Read(err)
			}
			textHashes[record.ContentRoot.Hash] = textHash
		}
		notesHash, found := noteHashes[record.NotesRoot.Hash]
		if !found {
			notes, decodeErr := decodeSnapshotNotes(session, record, notesLimit)
			if decodeErr != nil {
				return b, decodeErr
			}
			canonical, canonicalErr := vax.Canonical(notes)
			if canonicalErr != nil {
				return b, fault.Ensure(fault.StorageCorrupt, "筆記驗證失敗", canonicalErr)
			}
			notesHash = vax.Hash([]byte(canonical))
			noteHashes[record.NotesRoot.Hash] = notesHash
		}
		revision := record.Revision
		if err = verifier.AppendHashes(revision, textHash, notesHash); err != nil {
			return b, fault.Ensure(fault.StorageCorrupt, "VAX 歷史驗證失敗", err)
		}
		b.History = append(b.History, model.RevisionSummary{ID: revision.ID, Kind: revision.Kind, CreatedAt: revision.CreatedAt})
	}
	// Do not hold the chosen body while validating other historical notes.
	var retained int64
	for _, record := range records {
		if record.Revision.ID != snapshotID {
			continue
		}
		revision := record.Revision
		revision.Content, err = session.Text(record.ContentRoot, textLimit)
		if err != nil {
			return b, fault.Read(err)
		}
		revision.Notes, err = decodeSnapshotNotes(session, record, notesLimit)
		if err != nil {
			return b, err
		}
		b.Revisions = []model.Revision{revision}
		retained = record.ContentRoot.Bytes + record.NotesRoot.Bytes*2 + int64(len(revision.Notes))*80
		break
	}
	if len(b.Revisions) == 0 {
		return b, fault.New(fault.NotFound, "版本不在此主線")
	}
	b.RevisionCount = len(records)
	files := session.Files()
	// Cache the selected body and dependency descriptors, not every object's payload.
	retained += consumed - int64(len(source)) + int64(len(files))*96 + int64(len(b.History))*64
	if allowCache && snapshotID == m.RevisionIDs[len(m.RevisionIDs)-1] && retained <= int64(s.config.Storage.VerifiedCacheMiB)*1024*1024 {
		s.cacheMu.Lock()
		s.cache = &verifiedBook{key: key, book: cloneBook(b), objectMetaKey: metaKey, snapshotID: snapshotID,
			objectFiles: files, retainedBytes: retained}
		s.cacheMu.Unlock()
	}
	b.Progress = s.progress(m)
	return b, nil
}

func decodeSnapshotNotes(session *content.Session, record objectRevision, limit int64) ([]model.Note, error) {
	payload, err := session.Notes(record.NotesRoot, limit)
	if err != nil {
		return nil, fault.Read(err)
	}
	var notes []model.Note
	if err = json.Unmarshal(payload, &notes); err != nil {
		return nil, fault.Read(err)
	}
	return notes, nil
}

func (s *Store) readSnapshot(id, revision string) (model.Book, error) {
	m, err := s.manifest(id)
	if err != nil {
		return model.Book{}, err
	}
	if revision == "" {
		revision = m.RevisionIDs[len(m.RevisionIDs)-1]
	}
	present := false
	for _, candidate := range m.RevisionIDs {
		if candidate == revision {
			present = true
			break
		}
	}
	if !present {
		return model.Book{}, fault.New(fault.NotFound, "版本不在此主線")
	}
	if m.RevisionStorage != objectRevisionFormat {
		b, err := s.readBook(id)
		if err != nil {
			return b, err
		}
		return projectLegacySnapshot(b, revision)
	}
	folder, err := s.safe("books", id)
	if err != nil {
		return model.Book{}, err
	}
	return s.readObjectHistory(m, folder, true, revision)
}

func (s *Store) LoadReader(id string) (model.Book, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.readSnapshot(id, "")
}

func (s *Store) LoadRevision(id, revision string) (model.Revision, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	b, err := s.readSnapshot(id, revision)
	if err != nil {
		return model.Revision{}, err
	}
	for _, r := range b.Revisions {
		if r.ID == revision {
			return r, nil
		}
	}
	return model.Revision{}, fault.New(fault.NotFound, "版本不在此主線")
}

// All record/source/object bytes have already been rechecked against the cached
// chain. Materialize a historical selection without evicting the head cache.
func (s *Store) snapshotFromVerified(head model.Book, m model.Manifest, records []objectRevision,
	objects *content.Store, budget int64, id string) (model.Book, error) {
	b := cloneBook(head)
	session := objects.Session(budget, s.config.Storage.ObjectCount)
	for _, record := range records {
		if record.Revision.ID != id {
			continue
		}
		r := record.Revision
		var err error
		r.Content, err = session.Text(record.ContentRoot, int64(s.config.Limits.TextMiB)*1024*1024)
		if err != nil {
			return b, fault.Read(err)
		}
		r.Notes, err = decodeSnapshotNotes(session, record, int64(s.config.Limits.SnapshotNotesMiB)*1024*1024)
		if err != nil {
			return b, err
		}
		b.Revisions = []model.Revision{r}
		b.Progress = s.progress(m)
		return b, nil
	}
	return b, fault.New(fault.NotFound, "版本不在此主線")
}

func projectLegacySnapshot(b model.Book, id string) (model.Book, error) {
	history := make([]model.RevisionSummary, 0, len(b.Revisions))
	var selected *model.Revision
	for i, r := range b.Revisions {
		history = append(history, model.RevisionSummary{ID: r.ID, Kind: r.Kind, CreatedAt: r.CreatedAt})
		if r.ID == id {
			selected = &b.Revisions[i]
		}
	}
	if selected == nil {
		return model.Book{}, fault.New(fault.NotFound, "版本不在此主線")
	}
	b.History, b.RevisionCount = history, len(b.Revisions)
	b.Revisions = []model.Revision{*selected}
	return b, nil
}
