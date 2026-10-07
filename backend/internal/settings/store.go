// Package settings persists opaque client-owned JSON objects.
// It owns storage limits and optimistic concurrency, not UI schemas or defaults.
package settings

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"sync"
	"unicode/utf8"

	"github.com/bnggbn/Pageforge-Native/backend/internal/fault"
)

var ErrConflict = fault.New(fault.Conflict, "client settings changed; reload before saving")

type Snapshot struct {
	Document json.RawMessage `json:"document"`
	Revision string          `json:"revision"`
}

type Store struct {
	defaults, override string
	maxBytes           int64
	mu                 sync.Mutex
}

// New receives fixed paths from the composition root, never from HTTP input.
func New(defaults, override string, maxBytes int64) *Store {
	return &Store{defaults: defaults, override: override, maxBytes: maxBytes}
}

func (s *Store) MaxBytes() int64 { return s.maxBytes }

func (s *Store) Load() (Snapshot, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.load()
}

func (s *Store) load() (Snapshot, error) {
	data, err := s.read(s.override)
	if os.IsNotExist(err) {
		data, err = s.read(s.defaults)
	}
	if err != nil {
		return Snapshot{}, fault.Read(err)
	}
	if err = s.validate(data, fault.StorageCorrupt); err != nil {
		return Snapshot{}, err
	}
	return snapshot(data), nil
}

func (s *Store) read(filePath string) ([]byte, error) {
	if s.maxBytes <= 0 {
		return nil, fault.New(fault.Internal, "invalid client settings storage limit")
	}
	file, err := os.Open(filePath)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	stat, err := file.Stat()
	if err != nil {
		return nil, err
	}
	if !stat.Mode().IsRegular() {
		return nil, fault.New(fault.StorageCorrupt, "client settings must be a regular file")
	}
	if stat.Size() > s.maxBytes {
		return nil, fault.New(fault.LimitExceeded, "client settings exceed the storage limit")
	}
	return io.ReadAll(io.LimitReader(file, s.maxBytes+1))
}

func (s *Store) validate(data []byte, invalid fault.Code) error {
	if s.maxBytes <= 0 {
		return fault.New(fault.Internal, "invalid client settings storage limit")
	}
	if int64(len(data)) > s.maxBytes {
		return fault.New(fault.LimitExceeded, "client settings exceed the storage limit")
	}
	value := bytes.TrimSpace(data)
	if len(value) == 0 || value[0] != '{' || !utf8.Valid(value) || !json.Valid(value) {
		return fault.New(invalid, "client settings must contain one valid UTF-8 JSON object")
	}
	return nil
}

func (s *Store) Save(document json.RawMessage, expected string) (Snapshot, error) {
	// Own the bytes before checking, hashing and writing the candidate.
	data := bytes.Clone(document)
	if err := s.validate(data, fault.InvalidRequest); err != nil {
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
	// The temporary file must live beside the target for the final rename.
	file, err := os.CreateTemp(filepath.Dir(s.override), ".pageforge-settings-*")
	if err != nil {
		return Snapshot{}, fault.Write(err)
	}
	temporary := file.Name()
	defer os.Remove(temporary)
	if _, err = file.Write(data); err == nil {
		err = file.Sync()
	}
	closeErr := file.Close()
	if err != nil {
		return Snapshot{}, fault.Write(err)
	}
	if closeErr != nil {
		return Snapshot{}, fault.Write(closeErr)
	}
	if err = os.Rename(temporary, s.override); err != nil {
		return Snapshot{}, fault.Write(err)
	}
	return snapshot(data), nil
}

func snapshot(data []byte) Snapshot {
	hash := sha256.Sum256(data)
	return Snapshot{Document: bytes.Clone(data), Revision: hex.EncodeToString(hash[:])}
}
