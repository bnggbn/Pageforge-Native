package library

import (
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/bnggbn/Pageforge-Native/backend/internal/fault"
)

// AtomicJSON never truncates the visible record. A failed rename leaves the old head intact.
func atomicJSON(file string, value any) error {
	bytes, err := json.Marshal(value)
	if err != nil {
		return fault.Encode(err)
	}
	temporary, err := os.CreateTemp(filepath.Dir(file), ".pending-*.json")
	if err != nil {
		return fault.Write(err)
	}
	name := temporary.Name()
	defer os.Remove(name)
	if _, err = temporary.Write(bytes); err == nil {
		err = temporary.Sync()
	}
	closeErr := temporary.Close()
	if err != nil {
		return fault.Write(err)
	}
	if closeErr != nil {
		return fault.Write(closeErr)
	}
	return fault.Write(os.Rename(name, file))
}

func (s *Store) safe(parts ...string) (string, error) {
	file := filepath.Join(append([]string{s.root}, parts...)...)
	relative, err := filepath.Rel(s.root, file)
	if err != nil || relative == ".." || strings.HasPrefix(relative, ".."+string(os.PathSeparator)) {
		return "", fault.New(fault.UnsafePath, "資料夾路徑無效")
	}
	current := s.root
	for _, part := range strings.Split(relative, string(os.PathSeparator)) {
		current = filepath.Join(current, part)
		stat, err := os.Lstat(current)
		if err != nil {
			if errors.Is(err, os.ErrNotExist) {
				continue
			}
			return "", fault.Read(err)
		}
		if stat.Mode()&os.ModeSymlink != 0 {
			return "", fault.New(fault.UnsafePath, "不允許 library 連結檔")
		}
	}
	return file, nil
}
func readJSON(file string, value any) error {
	data, err := readBounded(file, 64*1024*1024)
	if err != nil {
		return fault.Read(err)
	}
	return fault.Read(json.Unmarshal(data, value))
}

func writeSource(file string, source []byte) error {
	stream, err := os.OpenFile(file, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		return fault.Write(err)
	}
	if _, err = stream.Write(source); err == nil {
		err = stream.Sync()
	}
	closeErr := stream.Close()
	if err != nil {
		return fault.Write(err)
	}
	return fault.Write(closeErr)
}

// LimitReader enforces the budget even when a file grows after opening.
func readBounded(file string, limit int64) ([]byte, error) {
	stream, err := os.Open(file)
	if err != nil {
		return nil, fault.Read(err)
	}
	defer stream.Close()
	stat, err := stream.Stat()
	if err != nil {
		return nil, fault.Read(err)
	}
	if !stat.Mode().IsRegular() {
		return nil, fault.New(fault.StorageCorrupt, "資料檔不是一般檔案")
	}
	if stat.Size() > limit {
		return nil, fault.New(fault.LimitExceeded, "資料檔超過讀取容量")
	}
	data, err := io.ReadAll(io.LimitReader(stream, limit+1))
	if err == nil && int64(len(data)) > limit {
		return nil, fault.New(fault.LimitExceeded, "資料檔超過讀取容量")
	}
	return data, fault.Read(err)
}
func (s *Store) readJSON(file string, value any) error {
	data, err := readBounded(file, int64(s.config.Storage.RecordMiB)*1024*1024)
	if err != nil {
		return fault.Read(err)
	}
	return fault.Read(json.Unmarshal(data, value))
}

// Check common ancestors once per history operation, then each UUID-named file.
// The file-level Lstat preserves rejection of links without repeating four parent checks per revision.
func revisionPath(folder, id string) (string, error) {
	if !uuid.MatchString(id) {
		return "", fault.New(fault.StorageCorrupt, "版本 ID 無效")
	}
	file := filepath.Join(folder, id+".json")
	stat, err := os.Lstat(file)
	if err != nil {
		return "", fault.Read(err)
	}
	if !stat.Mode().IsRegular() {
		return "", fault.New(fault.StorageCorrupt, "版本必須是一般檔案，不允許連結")
	}
	return file, nil
}
