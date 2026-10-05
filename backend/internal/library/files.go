package library

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// AtomicJSON never truncates the visible record. A failed rename leaves the old head intact.
func atomicJSON(file string, value any) error {
	bytes, err := json.Marshal(value)
	if err != nil {
		return err
	}
	temporary, err := os.CreateTemp(filepath.Dir(file), ".pending-*.json")
	if err != nil {
		return err
	}
	name := temporary.Name()
	defer os.Remove(name)
	if _, err = temporary.Write(bytes); err == nil {
		err = temporary.Sync()
	}
	closeErr := temporary.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	return os.Rename(name, file)
}

func (s *Store) safe(parts ...string) (string, error) {
	file := filepath.Join(append([]string{s.root}, parts...)...)
	relative, err := filepath.Rel(s.root, file)
	if err != nil || relative == ".." || strings.HasPrefix(relative, ".."+string(os.PathSeparator)) {
		return "", fmt.Errorf("資料夾路徑無效")
	}
	current := s.root
	for _, part := range strings.Split(relative, string(os.PathSeparator)) {
		current = filepath.Join(current, part)
		stat, err := os.Lstat(current)
		if err != nil {
			if os.IsNotExist(err) {
				continue
			}
			return "", err
		}
		if stat.Mode()&os.ModeSymlink != 0 {
			return "", fmt.Errorf("不允許 library 連結檔")
		}
	}
	return file, nil
}
func readJSON(file string, value any) error {
	data, err := os.ReadFile(file)
	if err != nil {
		return err
	}
	return json.Unmarshal(data, value)
}

func writeSource(file string, source []byte) error {
	stream, err := os.OpenFile(file, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	if _, err = stream.Write(source); err == nil {
		err = stream.Sync()
	}
	closeErr := stream.Close()
	if err != nil {
		return err
	}
	return closeErr
}
