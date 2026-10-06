package library

import (
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"sync"

	"github.com/bnggbn/Pageforge-Native/backend/internal/config"
	"github.com/bnggbn/Pageforge-Native/backend/internal/model"
	"github.com/bnggbn/Pageforge-Native/backend/internal/vax"
)

var ErrConflict = errors.New("版本已更新，請重新載入後比較；目前輸入仍保留")
var uuid = regexp.MustCompile(`(?i)^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$`)
var extensions = map[string]string{"markdown": "md", "text": "txt", "pdf": "pdf", "epub": "epub", "xlsx": "xlsx"}

type Store struct {
	root    string
	config  config.Config
	mu      sync.RWMutex
	lock    string
	cacheMu sync.Mutex
	cache   *verifiedBook
}

func Open(c config.Config) (*Store, error) {
	s := &Store{root: c.Paths.LibraryRoot, config: c}
	if stat, err := os.Lstat(s.root); err == nil && stat.Mode()&os.ModeSymlink != 0 {
		return nil, fmt.Errorf("library 根目錄不可為連結")
	} else if err != nil && !os.IsNotExist(err) {
		return nil, err
	}
	for _, folder := range []string{"books", "collection", ".pageforge", ".trash"} {
		location, err := s.safe(folder)
		if err != nil {
			return nil, err
		}
		if err = os.MkdirAll(location, 0700); err != nil {
			return nil, err
		}
	}
	s.lock = filepath.Join(s.root, ".pageforge", "server.lock")
	lock, err := os.OpenFile(s.lock, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		return nil, fmt.Errorf("library 正由其他程序使用，請先關閉 Web／桌面服務：%w", err)
	}
	_, err = lock.WriteString(strconv.Itoa(os.Getpid()))
	if err == nil {
		err = lock.Sync()
	}
	closeErr := lock.Close()
	if err == nil {
		err = closeErr
	}
	if err != nil {
		os.Remove(s.lock)
		return nil, err
	}
	return s, nil
}
func (s *Store) Close() error {
	data, err := os.ReadFile(s.lock)
	if err == nil && string(data) == strconv.Itoa(os.Getpid()) {
		return os.Remove(s.lock)
	}
	return err
}
func (s *Store) manifest(id string) (model.Manifest, error) {
	var m model.Manifest
	if !uuid.MatchString(id) {
		return m, fmt.Errorf("文件 ID 無效")
	}
	file, err := s.safe("books", id, "manifest.json")
	if err != nil {
		return m, err
	}
	if err = s.readJSON(file, &m); err != nil {
		return m, err
	}
	if (m.RevisionStorage != "" && m.RevisionStorage != objectRevisionFormat) ||
		m.Document.ID != id || extensions[m.Document.Format] == "" ||
		m.OriginalFile != "original."+extensions[m.Document.Format] || len(m.RevisionIDs) == 0 || len(m.RevisionIDs) > s.config.Limits.RevisionCount {
		return m, fmt.Errorf("文件 manifest 無效")
	}
	for _, revision := range m.RevisionIDs {
		if !uuid.MatchString(revision) {
			return m, fmt.Errorf("版本 ID 無效")
		}
	}
	return m, nil
}
func (s *Store) readBook(id string) (model.Book, error) {
	var b model.Book
	m, err := s.manifest(id)
	if err != nil {
		return b, err
	}
	if m.RevisionStorage == objectRevisionFormat {
		return s.readObjectBook(m)
	}
	b.Document = m.Document
	b.Revisions = []model.Revision{}
	b.OriginalPath, err = s.safe("books", id, m.OriginalFile)
	if err != nil {
		return b, err
	}
	key, size, err := s.historyFingerprint(m, b.OriginalPath)
	if err != nil {
		return b, err
	}
	s.cacheMu.Lock()
	cached := s.cache
	if cached != nil && cached.key == key {
		b = cloneBook(cached.book)
		s.cacheMu.Unlock()
		b.Progress = s.progress(m)
		return b, nil
	}
	s.cacheMu.Unlock()
	source, err := readBounded(b.OriginalPath, int64(s.config.Limits.DocumentMiB)*1024*1024)
	if err != nil {
		return b, err
	}
	loadedDigest, err := historyDigest(m)
	if err != nil {
		return b, err
	}
	appendFingerprint(loadedDigest, source)
	consumed := int64(len(source))
	versions, err := s.safe("books", id, "versions")
	if err != nil {
		return b, err
	}
	for _, revisionID := range m.RevisionIDs {
		file, err := revisionPath(versions, revisionID)
		if err != nil {
			return b, err
		}
		var revision model.Revision
		limit := int64(s.config.Storage.RecordMiB) * 1024 * 1024
		remaining := int64(s.config.Storage.HistoryMiB)*1024*1024 - consumed
		if remaining < limit {
			limit = remaining
		}
		data, err := readBounded(file, limit)
		if err != nil {
			return b, err
		}
		consumed += int64(len(data))
		appendFingerprint(loadedDigest, data)
		if err = json.Unmarshal(data, &revision); err != nil {
			return b, err
		}
		if revision.ID != revisionID {
			return b, fmt.Errorf("版本檔名不一致")
		}
		b.Revisions = append(b.Revisions, revision)
	}
	if err = vax.Verify(b.Document, source, b.Revisions); err != nil {
		return b, err
	}
	// The cache key must identify the exact bytes passed to VAX, including external-write races.
	if key != hex.EncodeToString(loadedDigest.Sum(nil)) {
		return b, fmt.Errorf("歷史在驗證時被外部修改，請重新載入")
	}
	if size <= int64(s.config.Storage.VerifiedCacheMiB)*1024*1024 {
		s.cacheMu.Lock()
		s.cache = &verifiedBook{key: key, book: cloneBook(b)}
		s.cacheMu.Unlock()
	}
	b.Progress = s.progress(m)
	return b, nil
}
func (s *Store) Load(id string) (model.Book, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.readBook(id)
}
func (s *Store) List() ([]model.Summary, error) { s.mu.RLock(); defer s.mu.RUnlock(); return s.list() }
func (s *Store) list() ([]model.Summary, error) {
	entries, err := os.ReadDir(filepath.Join(s.root, "books"))
	if err != nil {
		return nil, err
	}
	result := []model.Summary{}
	for _, entry := range entries {
		if !uuid.MatchString(entry.Name()) {
			continue
		}
		m, err := s.manifest(entry.Name())
		if err != nil {
			return nil, err
		}
		percentage := 0.0
		if progress := s.progress(m); progress != nil {
			percentage = progress.Percentage
		}
		result = append(result, model.Summary{ID: m.Document.ID, Title: m.Document.Title, Filename: m.Document.Filename,
			Format: m.Document.Format, UpdatedAt: m.Document.UpdatedAt, Head: m.RevisionIDs[len(m.RevisionIDs)-1],
			RevisionCount: len(m.RevisionIDs), Progress: percentage})
	}
	sort.Slice(result, func(i, j int) bool { return result[i].UpdatedAt > result[j].UpdatedAt })
	return result, nil
}
func (s *Store) progress(m model.Manifest) *model.Position {
	file, err := s.safe("books", m.Document.ID, "progress.json")
	if err != nil {
		return nil
	}
	var value model.Position
	data, err := readBounded(file, 16*1024)
	if err == nil {
		err = json.Unmarshal(data, &value)
	}
	if err != nil {
		if os.IsNotExist(err) {
			return m.Progress
		}
		return nil
	}
	if sameEpoch(value.Epoch, m.ProgressEpoch) {
		for _, id := range m.RevisionIDs {
			if id == value.RevisionID {
				return &value
			}
		}
	}
	return nil
}
func sameEpoch(a, b *string) bool { return a == nil && b == nil || a != nil && b != nil && *a == *b }
