package library

import (
	"os"
	"path/filepath"
	"strings"
	"unicode/utf8"

	"github.com/bnggbn/Pageforge-Native/backend/internal/fault"
	"github.com/bnggbn/Pageforge-Native/backend/internal/model"
	"github.com/bnggbn/Pageforge-Native/backend/internal/vax"
)

func (s *Store) Import(filename string, source []byte) (string, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	index, err := s.importIndex()
	if err != nil {
		return "", false, err
	}
	return s.importWithIndex(filename, source, index)
}
func (s *Store) importIndex() (map[string]string, error) {
	entries, err := os.ReadDir(filepath.Join(s.root, "books"))
	if err != nil {
		return nil, fault.Read(err)
	}
	index := map[string]string{}
	for _, entry := range entries {
		if !uuid.MatchString(entry.Name()) {
			continue
		}
		m, err := s.manifest(entry.Name())
		if err != nil {
			return nil, err
		}
		index[m.Document.Format+":"+m.Document.OriginalHash] = m.Document.ID
	}
	return index, nil
}
func (s *Store) importWithIndex(filename string, source []byte, index map[string]string) (string, bool, error) {
	if filename != filepath.Base(filename) || strings.ContainsAny(filename, "\\\x00") {
		return "", false, fault.New(fault.InvalidRequest, "invalid filename")
	}
	extension := strings.ToLower(filepath.Ext(filename))
	format := ""
	if extension == ".md" || extension == ".markdown" {
		format = "markdown"
	} else if extension == ".txt" {
		format = "text"
	}
	if format == "" {
		return "", false, fault.New(fault.InvalidRequest, "import currently supports Markdown and TXT; other formats require existing library projections")
	}
	text := strings.TrimPrefix(string(source), "\ufeff")
	if len(source) > s.config.Limits.TextMiB*1024*1024 {
		return "", false, fault.New(fault.LimitExceeded, "document exceeds the configured limit")
	}
	if len(source) == 0 || !utf8.Valid(source) ||
		strings.TrimSpace(text) == "" || strings.ContainsRune(text, 0) {
		return "", false, fault.New(fault.InvalidRequest, "content must be nonempty UTF-8 text within the configured limit")
	}
	hash := vax.Hash(source)
	if id, found := index[format+":"+hash]; found {
		return id, true, nil
	}
	id := vax.UUID()
	actor := "pageforge:" + id
	salt, genesis := vax.NewGenesis(actor)
	now := vax.Now()
	doc := model.Document{ID: id, Actor: actor, Salt: salt, Genesis: genesis, Title: strings.TrimSuffix(filename, filepath.Ext(filename)),
		Filename: filename, Format: format, CreatedAt: now, UpdatedAt: now, OriginalHash: hash, Sections: []model.Section{}, Sheets: []model.Sheet{}}
	revision, err := vax.Create(doc, nil, "import", text, nil, nil)
	if err != nil {
		return "", false, err
	}
	booksDir := filepath.Join(s.root, "books")
	pending, err := os.MkdirTemp(booksDir, ".pending-")
	if err != nil {
		return "", false, fault.Write(err)
	}
	defer os.RemoveAll(pending)
	if err = os.Mkdir(filepath.Join(pending, "versions"), 0700); err != nil {
		return "", false, fault.Write(err)
	}
	original := "original." + extensions[format]
	if err = writeSource(filepath.Join(pending, original), source); err != nil {
		return "", false, err
	}
	storageFormat := ""
	if s.config.Storage.RevisionFormat == objectRevisionFormat {
		storageFormat = objectRevisionFormat
	}
	if err = s.writeRevision(pending, storageFormat, revision); err != nil {
		return "", false, err
	}
	manifest := model.Manifest{
		RevisionStorage: storageFormat, Document: doc,
		OriginalFile: original, OriginalType: "text/plain", RevisionIDs: []string{revision.ID},
	}
	if err = atomicJSON(filepath.Join(pending, "manifest.json"), manifest); err != nil {
		return "", false, err
	}
	if storageFormat == objectRevisionFormat {
		if _, err = s.readObjectBookAt(manifest, pending, false); err != nil {
			return "", false, err
		}
	}
	if err = os.Rename(pending, filepath.Join(booksDir, id)); err != nil {
		return "", false, fault.Write(err)
	}
	index[format+":"+hash] = id
	return id, false, nil
}
func (s *Store) SyncCollection() (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	index, err := s.importIndex()
	if err != nil {
		return 0, err
	}
	entries, err := os.ReadDir(filepath.Join(s.root, "collection"))
	if err != nil {
		return 0, fault.Read(err)
	}
	count := 0
	for _, entry := range entries {
		extension := strings.ToLower(filepath.Ext(entry.Name()))
		if entry.IsDir() || (extension != ".txt" && extension != ".md" && extension != ".markdown") {
			continue
		}
		file, err := s.safe("collection", entry.Name())
		if err != nil {
			return count, err
		}
		bytes, err := readBounded(file, int64(s.config.Limits.TextMiB)*1024*1024)
		if err != nil {
			return count, err
		}
		_, duplicate, err := s.importWithIndex(entry.Name(), bytes, index)
		if err != nil {
			return count, err
		}
		if !duplicate {
			count++
		}
	}
	return count, nil
}
