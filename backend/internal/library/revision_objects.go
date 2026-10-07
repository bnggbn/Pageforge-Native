package library

import (
	"encoding/json"
	"path/filepath"

	"github.com/bnggbn/Pageforge-Native/backend/internal/content"
	"github.com/bnggbn/Pageforge-Native/backend/internal/fault"
	"github.com/bnggbn/Pageforge-Native/backend/internal/model"
	"github.com/bnggbn/Pageforge-Native/backend/internal/vax"
)

const objectRevisionFormat = "objects-v1"

type objectRevision struct {
	StorageVersion int            `json:"storageVersion"`
	Revision       model.Revision `json:"revision"`
	ContentRoot    content.Ref    `json:"contentRoot"`
	NotesRoot      content.Ref    `json:"notesRoot"`
}

func (s *Store) objectStore(folder string) (*content.Store, error) {
	maxBlob := max(int64(content.MaxChunk), int64(s.config.Limits.SnapshotNotesMiB)*1024*1024)
	options := content.Options{
		InlineBytes: s.config.Storage.InlineObjectBytes,
		CatalogMiB:  s.config.Storage.ObjectCatalogMiB,
		MaxObjects:  s.config.Storage.ObjectCount,
	}
	return content.OpenWithOptions(filepath.Join(folder, "objects"), maxBlob, options)
}

// Only new imports select their storage format. Existing immutable revisions remain unchanged.
func (s *Store) writeRevision(folder, format string, revision model.Revision) error {
	relative, err := filepath.Rel(s.root, folder)
	if err != nil {
		return fault.Read(err)
	}
	file, err := s.safe(relative, "versions", revision.ID+".json")
	if err != nil {
		return fault.Read(err)
	}
	if format == "" {
		return atomicJSON(file, revision)
	}
	if format != objectRevisionFormat {
		return fault.New(fault.UnsupportedStorage, "unsupported revision storage")
	}
	objects, err := s.objectStore(folder)
	if err != nil {
		return fault.Read(err)
	}
	text, err := objects.PutText(revision.Content)
	if err != nil {
		return fault.Read(err)
	}
	data, err := json.Marshal(revision.Notes)
	if err != nil {
		return fault.Encode(err)
	}
	notes, err := objects.PutNotes(data)
	if err != nil {
		return fault.Read(err)
	}
	if err = objects.Flush(); err != nil {
		return fault.Read(err)
	}
	revision.Content = ""
	revision.Notes = nil
	record := objectRevision{StorageVersion: 1, Revision: revision, ContentRoot: text, NotesRoot: notes}
	encoded, err := json.Marshal(record)
	if err != nil {
		return fault.Encode(err)
	}
	if int64(len(encoded)) > int64(s.config.Storage.RecordMiB)*1024*1024 {
		return fault.New(fault.LimitExceeded, "revision data exceeds the read limit")
	}
	return atomicJSON(file, record)
}

func decodeObjectRevision(data []byte, id string) (objectRevision, error) {
	var record objectRevision
	if err := json.Unmarshal(data, &record); err != nil {
		return record, fault.Read(err)
	}
	if record.StorageVersion < 1 {
		return record, fault.New(fault.StorageCorrupt, "missing object revision storage version")
	}
	if record.StorageVersion != 1 {
		return record, fault.New(fault.UnsupportedStorage, "unsupported revision storage version")
	}
	if record.Revision.ID != id || record.Revision.Content != "" || record.Revision.Notes != nil {
		return record, fault.New(fault.StorageCorrupt, "invalid object revision record")
	}
	return record, nil
}

// Layout persistence needs only this head's notes, not all text objects or historical bodies.
func (s *Store) revisionNotes(m model.Manifest, id string) ([]model.Note, error) {
	file, err := s.safe("books", m.Document.ID, "versions", id+".json")
	if err != nil {
		return nil, fault.Read(err)
	}
	if m.RevisionStorage == "" {
		var revision model.Revision
		if err = s.readJSON(file, &revision); err != nil {
			return nil, fault.Read(err)
		}
		return revision.Notes, nil
	}
	data, err := readBounded(file, int64(s.config.Storage.RecordMiB)*1024*1024)
	if err != nil {
		return nil, fault.Read(err)
	}
	record, err := decodeObjectRevision(data, id)
	if err != nil {
		return nil, fault.Read(err)
	}
	folder, err := s.safe("books", m.Document.ID)
	if err != nil {
		return nil, fault.Read(err)
	}
	objects, err := s.objectStore(folder)
	if err != nil {
		return nil, fault.Read(err)
	}
	session := objects.Session(int64(s.config.Storage.HistoryMiB)*1024*1024, s.config.Storage.ObjectCount)
	payload, err := session.Notes(record.NotesRoot, int64(s.config.Limits.SnapshotNotesMiB)*1024*1024)
	if err != nil {
		return nil, fault.Read(err)
	}
	var notes []model.Note
	if err = json.Unmarshal(payload, &notes); err != nil {
		return nil, fault.Read(err)
	}
	canonical, err := vax.Canonical(notes)
	if err != nil {
		return nil, fault.Read(err)
	}
	var envelope struct {
		SDTO struct {
			NotesHash string `json:"notesHash"`
		} `json:"sdto"`
	}
	if err = json.Unmarshal([]byte(record.Revision.Envelope), &envelope); err != nil {
		return nil, fault.Read(err)
	}
	if vax.Hash([]byte(canonical)) != envelope.SDTO.NotesHash {
		return nil, fault.New(fault.StorageCorrupt, "note content does not match the revision commitment")
	}
	return notes, nil
}
