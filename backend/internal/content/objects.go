// Package content stores immutable, typed, content-addressed objects.
package content

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
)

const (
	textKind   byte = 0
	branchKind byte = 1
	notesKind  byte = 2
	MaxChunk        = 64 * 1024
	MinChunk        = 16 * 1024
	Fanout          = 16
	maxDepth        = 32
)

var magic = []byte("PFCO\x01")
var validHash = regexp.MustCompile(`^[0-9a-f]{64}$`)

type Ref struct {
	Hash  string `json:"hash"`
	Bytes int64  `json:"bytes"`
}

type Store struct {
	inline          map[string][]byte
	inlineBytes     int
	catalogLimit    int64
	catalogCount    int
	catalogEstimate int64
	catalogDirty    bool
	root            string
	maxBlob         int64
}

func Open(root string, maxBlob int64) (*Store, error) {
	return OpenWithOptions(root, maxBlob, Options{CatalogMiB: 8, MaxObjects: 100000})
}

func OpenWithOptions(root string, maxBlob int64, options Options) (*Store, error) {
	if maxBlob < MaxChunk {
		return nil, fmt.Errorf("invalid object capacity")
	}
	if err := checkPath(root); err != nil {
		return nil, err
	}
	if options.InlineBytes < 0 || options.InlineBytes > MaxChunk ||
		options.CatalogMiB < 1 || options.CatalogMiB > 32 ||
		options.MaxObjects < 1 || options.MaxObjects > 1000000 {
		return nil, fmt.Errorf("invalid object catalog options")
	}
	s := &Store{
		root: root, maxBlob: maxBlob, inlineBytes: options.InlineBytes,
		catalogLimit: int64(options.CatalogMiB) * 1024 * 1024,
		catalogCount: options.MaxObjects,
	}
	if err := s.loadCatalog(); err != nil {
		return nil, err
	}
	return s, nil
}

func checkPath(file string) error {
	current := filepath.Clean(file)
	for {
		info, err := os.Lstat(current)
		if err != nil && !os.IsNotExist(err) {
			return err
		}
		if err == nil && info.Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("object path cannot contain links")
		}
		parent := filepath.Dir(current)
		if parent == current {
			return nil
		}
		current = parent
	}
}

func (s *Store) location(hash string) (string, error) {
	if !validHash.MatchString(hash) {
		return "", fmt.Errorf("invalid object hash")
	}
	file := filepath.Join(s.root, hash[:2], hash+".pfo")
	return file, checkPath(file)
}

func (s *Store) read(hash string) ([]byte, error) {
	return s.readInSession(hash, nil, s.maxBlob+int64(len(magic))+1)
}

func (s *Store) openObject(hash string, checkedDirs map[string]bool) (*os.File, os.FileInfo, error) {
	if !validHash.MatchString(hash) {
		return nil, nil, fmt.Errorf("invalid object hash")
	}
	file := filepath.Join(s.root, hash[:2], hash+".pfo")
	if checkedDirs == nil {
		if err := checkPath(file); err != nil {
			return nil, nil, err
		}
	} else {
		folder := filepath.Dir(file)
		if !checkedDirs[folder] {
			info, err := os.Lstat(folder)
			if err != nil {
				return nil, nil, err
			}
			if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
				return nil, nil, fmt.Errorf("object shard must be a directory without links")
			}
			checkedDirs[folder] = true
		}
	}
	info, err := os.Lstat(file)
	if err != nil {
		return nil, nil, err
	}
	if !info.Mode().IsRegular() || info.Size() > s.maxBlob+int64(len(magic))+1 {
		return nil, nil, fmt.Errorf("invalid object file or capacity")
	}
	f, err := os.Open(file)
	if err != nil {
		return nil, nil, err
	}
	return f, info, nil
}

func (s *Store) readInSession(hash string, checkedDirs map[string]bool, remaining int64) ([]byte, error) {
	if remaining < 0 {
		return nil, fmt.Errorf("object history capacity exceeded")
	}
	if wire, found := s.inline[hash]; found {
		if int64(len(wire)) > remaining {
			return nil, fmt.Errorf("object history capacity exceeded")
		}
		if err := verifyWire(wire, hash); err != nil {
			return nil, err
		}
		return append([]byte(nil), wire...), nil
	}
	f, info, err := s.openObject(hash, checkedDirs)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	if info.Size() > remaining {
		return nil, fmt.Errorf("object history capacity exceeded")
	}
	data := make([]byte, int(info.Size()))
	if _, err = io.ReadFull(f, data); err != nil {
		return nil, err
	}
	var extra [1]byte
	if n, readErr := f.Read(extra[:]); n != 0 || readErr != io.EOF {
		return nil, fmt.Errorf("object changed size while reading")
	}
	digest := sha256.Sum256(data)
	if hex.EncodeToString(digest[:]) != hash || len(data) < len(magic)+1 || !bytes.Equal(data[:len(magic)], magic) {
		return nil, fmt.Errorf("object hash or format mismatch")
	}
	return data, nil
}

func (s *Store) put(kind byte, payload []byte, size int64) (Ref, error) {
	if int64(len(payload)) > s.maxBlob {
		return Ref{}, fmt.Errorf("object exceeds capacity")
	}
	data := make([]byte, len(magic)+1+len(payload))
	copy(data, magic)
	data[len(magic)] = kind
	copy(data[len(magic)+1:], payload)
	sum := sha256.Sum256(data)
	ref := Ref{Hash: hex.EncodeToString(sum[:]), Bytes: size}
	if existing, found := s.inline[ref.Hash]; found {
		if err := verifyWire(existing, ref.Hash); err != nil {
			return Ref{}, err
		}
		if !bytes.Equal(existing, data) {
			return Ref{}, fmt.Errorf("object collision")
		}
		return ref, nil
	}
	file, err := s.location(ref.Hash)
	if err != nil {
		return Ref{}, err
	}
	if existing, err := s.read(ref.Hash); err == nil {
		if !bytes.Equal(existing, data) {
			return Ref{}, fmt.Errorf("object collision")
		}
		return ref, nil
	} else if !os.IsNotExist(err) {
		return Ref{}, err
	}
	if s.stageInline(ref, data) {
		return ref, nil
	}
	if err = os.MkdirAll(filepath.Dir(file), 0700); err != nil {
		return Ref{}, err
	}
	if err = checkPath(file); err != nil {
		return Ref{}, err
	}
	pending, err := os.CreateTemp(filepath.Dir(file), ".pending-*.pfo")
	if err != nil {
		return Ref{}, err
	}
	name := pending.Name()
	defer os.Remove(name)
	if _, err = pending.Write(data); err == nil {
		err = pending.Sync()
	}
	closeErr := pending.Close()
	if err != nil {
		return Ref{}, err
	}
	if closeErr != nil {
		return Ref{}, closeErr
	}
	// Hard-link publication is atomic and cannot overwrite an existing immutable object.
	if err = os.Link(name, file); err != nil {
		existing, readErr := s.read(ref.Hash)
		if readErr != nil || !bytes.Equal(existing, data) {
			return Ref{}, fmt.Errorf("publish object: %w", err)
		}
	}
	return ref, nil
}

func (s *Store) PutNotes(data []byte) (Ref, error) { return s.put(notesKind, data, int64(len(data))) }
