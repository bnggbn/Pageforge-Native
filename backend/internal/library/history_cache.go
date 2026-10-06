package library

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"hash"
	"io"
	"os"

	"github.com/bnggbn/Pageforge-Native/backend/internal/content"
	"github.com/bnggbn/Pageforge-Native/backend/internal/fault"
	"github.com/bnggbn/Pageforge-Native/backend/internal/model"
)

// One bounded, immutable verified history. File contents, not timestamps, define identity.
type verifiedBook struct {
	objectMetaKey string
	objectFiles   []content.StoredFile
	retainedBytes int64
	key           string
	book          model.Book
}

func (s *Store) historyFingerprint(m model.Manifest, original string) (string, int64, error) {
	digest, err := historyDigest(m)
	if err != nil {
		return "", 0, fault.Read(err)
	}
	var total int64
	buffer := make([]byte, 32*1024)
	fingerprint := func(file string, limit int64) error {
		stream, err := os.Open(file)
		if err != nil {
			return fault.Read(err)
		}
		defer stream.Close()
		stat, err := stream.Stat()
		if err != nil {
			return fault.Read(err)
		}
		if !stat.Mode().IsRegular() {
			return fault.New(fault.StorageCorrupt, "歷史檔案不是一般檔案")
		}
		if stat.Size() > limit {
			return fault.New(fault.LimitExceeded, "歷史資料超過讀取容量")
		}
		hash := sha256.New()
		remaining := int64(s.config.Storage.HistoryMiB)*1024*1024 - total
		if remaining < limit {
			limit = remaining
		}
		count, err := io.CopyBuffer(hash, io.LimitReader(stream, limit+1), buffer)
		if err != nil {
			return fault.Read(err)
		}
		if count > limit {
			return fault.New(fault.LimitExceeded, "整本歷史超過讀取容量；請調整 storage.historyMiB")
		}
		total += count
		digest.Write(hash.Sum(nil))
		return nil
	}
	if err = fingerprint(original, int64(s.config.Limits.DocumentMiB)*1024*1024); err != nil {
		return "", 0, fault.Read(err)
	}
	versions, err := s.safe("books", m.Document.ID, "versions")
	if err != nil {
		return "", 0, fault.Read(err)
	}
	for _, id := range m.RevisionIDs {
		file, err := revisionPath(versions, id)
		if err != nil {
			return "", 0, fault.Read(err)
		}
		if err = fingerprint(file, int64(s.config.Storage.RecordMiB)*1024*1024); err != nil {
			return "", 0, fault.Read(err)
		}
	}
	return hex.EncodeToString(digest.Sum(nil)), total, nil
}

// Copy mutable slices and optional fields; strings can safely share immutable bytes.
func cloneBook(b model.Book) model.Book {
	b.Sections = append([]model.Section{}, b.Sections...)
	b.Sheets = append([]model.Sheet{}, b.Sheets...)
	for i := range b.Sheets {
		rows := make([][]string, len(b.Sheets[i].Rows))
		for j, row := range b.Sheets[i].Rows {
			rows[j] = append([]string{}, row...)
		}
		b.Sheets[i].Rows = rows
	}
	b.Revisions = append([]model.Revision{}, b.Revisions...)
	for i := range b.Revisions {
		r := &b.Revisions[i]
		r.Notes = append([]model.Note{}, r.Notes...)
		if r.ParentID != nil {
			id := *r.ParentID
			r.ParentID = &id
		}
		if r.AdoptedFrom != nil {
			source := *r.AdoptedFrom
			r.AdoptedFrom = &source
		}
	}
	b.Progress = nil
	return b
}

func historyDigest(m model.Manifest) (hash.Hash, error) {
	encoded, err := json.Marshal(struct {
		Storage  string
		Document model.Document
		IDs      []string
	}{m.RevisionStorage, m.Document, m.RevisionIDs})
	if err != nil {
		return nil, fault.Read(err)
	}
	digest := sha256.New()
	digest.Write(encoded)
	return digest, nil
}
func appendFingerprint(digest hash.Hash, data []byte) {
	sum := sha256.Sum256(data)
	digest.Write(sum[:])
}
