package library

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"unicode/utf8"

	"github.com/bnggbn/Pageforge-Native/backend/internal/model"
	"github.com/bnggbn/Pageforge-Native/backend/internal/vax"
)

func (s *Store) Import(filename string, source []byte) (string, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if filename != filepath.Base(filename) || strings.ContainsAny(filename, "\\\x00") {
		return "", false, fmt.Errorf("檔名無效")
	}
	extension := strings.ToLower(filepath.Ext(filename))
	format := ""
	if extension == ".md" || extension == ".markdown" {
		format = "markdown"
	} else if extension == ".txt" {
		format = "text"
	}
	if format == "" {
		return "", false, fmt.Errorf("此階段匯入支援 Markdown／TXT；其他格式可讀取既有 library 投影")
	}
	text := strings.TrimPrefix(string(source), "\ufeff")
	if len(source) == 0 || len(source) > s.config.Limits.TextMiB*1024*1024 || !utf8.Valid(source) ||
		strings.TrimSpace(text) == "" || strings.ContainsRune(text, 0) {
		return "", false, fmt.Errorf("需為非空白 UTF-8 文字，且不可超過設定容量")
	}
	hash := vax.Hash(source)
	books, err := s.list()
	if err != nil {
		return "", false, err
	}
	for _, item := range books {
		m, err := s.manifest(item.ID)
		if err != nil {
			return "", false, err
		}
		if m.Document.Format == format && m.Document.OriginalHash == hash {
			return item.ID, true, nil
		}
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
		return "", false, err
	}
	defer os.RemoveAll(pending)
	if err = os.Mkdir(filepath.Join(pending, "versions"), 0700); err != nil {
		return "", false, err
	}
	original := "original." + extensions[format]
	if err = writeSource(filepath.Join(pending, original), source); err != nil {
		return "", false, err
	}
	if err = atomicJSON(filepath.Join(pending, "versions", revision.ID+".json"), revision); err != nil {
		return "", false, err
	}
	manifest := model.Manifest{Document: doc, OriginalFile: original, OriginalType: "text/plain", RevisionIDs: []string{revision.ID}}
	if err = atomicJSON(filepath.Join(pending, "manifest.json"), manifest); err != nil {
		return "", false, err
	}
	if err = os.Rename(pending, filepath.Join(booksDir, id)); err != nil {
		return "", false, err
	}
	return id, false, nil
}
func (s *Store) SyncCollection() (int, error) {
	entries, err := os.ReadDir(filepath.Join(s.root, "collection"))
	if err != nil {
		return 0, err
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
		stat, err := os.Stat(file)
		if err != nil {
			return count, err
		}
		if stat.Size() > int64(s.config.Limits.TextMiB*1024*1024) {
			return count, fmt.Errorf("來源文件超過容量")
		}
		bytes, err := os.ReadFile(file)
		if err != nil {
			return count, err
		}
		_, duplicate, err := s.Import(entry.Name(), bytes)
		if err != nil {
			return count, err
		}
		if !duplicate {
			count++
		}
	}
	return count, nil
}
