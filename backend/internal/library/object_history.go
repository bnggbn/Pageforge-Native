package library

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/bnggbn/Pageforge-Native/backend/internal/model"
	"github.com/bnggbn/Pageforge-Native/backend/internal/vax"
)

func (s *Store) readObjectBook(m model.Manifest) (model.Book, error) {
	folder, err := s.safe("books", m.Document.ID)
	if err != nil {
		return model.Book{}, err
	}
	return s.readObjectBookAt(m, folder, true)
}

func (s *Store) readObjectBookAt(m model.Manifest, folder string, allowCache bool) (model.Book, error) {
	b := model.Book{Document: m.Document, Revisions: []model.Revision{}}
	relative, err := filepath.Rel(s.root, folder)
	if err != nil {
		return b, err
	}
	original, err := s.safe(relative, m.OriginalFile)
	if err != nil {
		return b, err
	}
	b.OriginalPath = original
	sourceLimit := min(s.config.Limits.DocumentMiB, s.config.Storage.HistoryMiB)
	sourceHash, sourceSize, err := fingerprintObjectSource(original, int64(sourceLimit)*1024*1024)
	if err != nil {
		return b, err
	}
	digest, err := historyDigest(m)
	if err != nil {
		return b, err
	}
	digest.Write(sourceHash)
	budget := int64(s.config.Storage.HistoryMiB) * 1024 * 1024
	consumed := sourceSize
	versions, err := s.safe(relative, "versions")
	if err != nil {
		return b, err
	}
	records := make([]objectRevision, 0, len(m.RevisionIDs))
	for _, id := range m.RevisionIDs {
		file, err := revisionPath(versions, id)
		if err != nil {
			return b, err
		}
		data, err := readBounded(file, min(int64(s.config.Storage.RecordMiB)*1024*1024, budget-consumed))
		if err != nil {
			return b, err
		}
		consumed += int64(len(data))
		appendFingerprint(digest, data)
		record, err := decodeObjectRevision(data, id)
		if err != nil {
			return b, err
		}
		records = append(records, record)
	}
	objects, err := s.objectStore(folder)
	if err != nil {
		return b, err
	}
	// Metadata includes actual original bytes, all revision records and the storage contract.
	metaKey := hex.EncodeToString(digest.Sum(nil))
	s.cacheMu.Lock()
	cached := s.cache
	s.cacheMu.Unlock()
	if allowCache && cached != nil && cached.objectMetaKey == metaKey &&
		cached.retainedBytes <= budget && cached.retainedBytes <= int64(s.config.Storage.VerifiedCacheMiB)*1024*1024 {
		textLimit := int64(s.config.Limits.TextMiB) * 1024 * 1024
		notesLimit := int64(s.config.Limits.SnapshotNotesMiB) * 1024 * 1024
		for _, record := range records {
			if record.ContentRoot.Bytes < 0 || record.ContentRoot.Bytes > textLimit ||
				record.NotesRoot.Bytes < 0 || record.NotesRoot.Bytes > notesLimit {
				return b, fmt.Errorf("版本展開容量超過限制")
			}
		}
		if err = objects.VerifyFiles(cached.objectFiles, budget-consumed, s.config.Storage.ObjectCount); err != nil {
			return b, err
		}
		b = cloneBook(cached.book)
		b.Progress = s.progress(m)
		return b, nil
	}
	session := objects.Session(budget-consumed, s.config.Storage.ObjectCount)
	textLimit := int64(s.config.Limits.TextMiB) * 1024 * 1024
	notesLimit := int64(s.config.Limits.SnapshotNotesMiB) * 1024 * 1024
	for _, record := range records {
		if err = session.VerifyText(record.ContentRoot, textLimit); err != nil {
			return b, err
		}
		if err = session.VerifyNotes(record.NotesRoot, notesLimit); err != nil {
			return b, err
		}
	}
	for _, hash := range session.Hashes() {
		bytes, _ := hex.DecodeString(hash)
		digest.Write(bytes)
	}
	key := hex.EncodeToString(digest.Sum(nil))
	source, err := readBounded(original, int64(s.config.Limits.DocumentMiB)*1024*1024)
	if err != nil {
		return b, err
	}
	if vax.Hash(source) != hex.EncodeToString(sourceHash) {
		return b, fmt.Errorf("原始檔在驗證時被外部修改")
	}
	// Bound reconstruction separately: tiny changes can share objects but yield many distinct strings.
	retained := consumed + session.Bytes
	texts := map[string]string{}
	notesByHash := map[string][]model.Note{}
	for _, record := range records {
		revision := record.Revision
		text, found := texts[record.ContentRoot.Hash]
		if !found {
			if record.ContentRoot.Bytes > budget-retained {
				return b, fmt.Errorf("還原歷史超過記憶體容量限制")
			}
			retained += record.ContentRoot.Bytes
			text, err = session.Text(record.ContentRoot, textLimit)
			if err != nil {
				return b, err
			}
			texts[record.ContentRoot.Hash] = text
		}
		notes, found := notesByHash[record.NotesRoot.Hash]
		if !found {
			if record.NotesRoot.Bytes > (budget-retained)/2 {
				return b, fmt.Errorf("還原筆記超過容量限制")
			}
			retained += record.NotesRoot.Bytes * 2
			payload, err := session.Notes(record.NotesRoot, notesLimit)
			if err != nil {
				return b, err
			}
			if err = json.Unmarshal(payload, &notes); err != nil {
				return b, err
			}
			notesByHash[record.NotesRoot.Hash] = notes
		}
		// Five Go string descriptors per Note; avoid aliasing mutable slices between revisions.
		weight := int64(len(notes)) * 80
		if weight > budget-retained {
			return b, fmt.Errorf("還原筆記索引超過容量限制")
		}
		retained += weight
		revision.Content = text
		revision.Notes = append([]model.Note{}, notes...)
		b.Revisions = append(b.Revisions, revision)
	}
	if err = vax.Verify(b.Document, source, b.Revisions); err != nil {
		return b, err
	}
	if allowCache && retained <= int64(s.config.Storage.VerifiedCacheMiB)*1024*1024 {
		s.cacheMu.Lock()
		s.cache = &verifiedBook{
			key: key, book: cloneBook(b), objectMetaKey: metaKey,
			objectFiles: session.Files(), retainedBytes: retained,
		}
		s.cacheMu.Unlock()
	}
	b.Progress = s.progress(m)
	return b, nil
}

// Warm reads hash the original without allocating a second full-text buffer.
func fingerprintObjectSource(file string, limit int64) ([]byte, int64, error) {
	info, err := os.Lstat(file)
	if err != nil {
		return nil, 0, err
	}
	if !info.Mode().IsRegular() || info.Size() > limit {
		return nil, 0, fmt.Errorf("原始檔超量或不是一般檔案")
	}
	stream, err := os.Open(file)
	if err != nil {
		return nil, 0, err
	}
	defer stream.Close()
	hash := sha256.New()
	size, err := io.CopyBuffer(hash, io.LimitReader(stream, limit+1), make([]byte, 32*1024))
	if err != nil {
		return nil, 0, err
	}
	if size > limit {
		return nil, 0, fmt.Errorf("原始檔超過容量")
	}
	return hash.Sum(nil), size, nil
}
