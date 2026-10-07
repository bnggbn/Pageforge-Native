package design

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sync"

	"github.com/bnggbn/Pageforge-Native/backend/internal/fault"
)

var ErrConflict = fault.New(fault.Conflict, "design changed in another window; reload before applying changes")

type Store struct {
	root string
	mu   sync.Mutex
}

func New(root string) *Store { return &Store{root: root} }
func (s *Store) Load() (Snapshot, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.load()
}
func (s *Store) load() (Snapshot, error) {
	data, err := read(filepath.Join(s.root, "pageforge.design.local.json"))
	if os.IsNotExist(err) {
		data, err = read(filepath.Join(s.root, "pageforge.design.json"))
	}
	if err != nil {
		return Snapshot{}, err
	}
	document, err := Decode(data)
	if err != nil {
		return Snapshot{}, fmt.Errorf("invalid design configuration: %w", err)
	}
	return snapshot(document), nil
}
func read(path string) ([]byte, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	data, err := io.ReadAll(io.LimitReader(file, MaxBytes+1))
	if len(data) > MaxBytes {
		return nil, fmt.Errorf("design configuration exceeds 16 KiB")
	}
	return data, err
}
func (s *Store) Save(document Document, expected string) (Snapshot, error) {
	if err := document.Validate(); err != nil {
		return Snapshot{}, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	current, err := s.load()
	if err != nil {
		return Snapshot{}, err
	}
	if current.Revision != expected {
		return Snapshot{}, ErrConflict
	}
	data, err := json.MarshalIndent(document, "", "  ")
	if err != nil {
		return Snapshot{}, err
	}
	file, err := os.CreateTemp(s.root, ".pageforge-design-*")
	if err != nil {
		return Snapshot{}, err
	}
	temporary := file.Name()
	defer os.Remove(temporary)
	if _, err = file.Write(append(data, '\n')); err == nil {
		err = file.Sync()
	}
	closeErr := file.Close()
	if err != nil {
		return Snapshot{}, err
	}
	if closeErr != nil {
		return Snapshot{}, closeErr
	}
	if err = os.Rename(temporary, filepath.Join(s.root, "pageforge.design.local.json")); err != nil {
		return Snapshot{}, err
	}
	return snapshot(document), nil
}
