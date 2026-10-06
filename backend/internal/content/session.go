package content

import (
	"encoding/binary"
	"encoding/hex"
	"sort"
	"strings"
	"unicode/utf8"

	"github.com/bnggbn/Pageforge-Native/backend/internal/fault"
)

type object struct {
	kind     byte
	payload  []byte
	children []Ref
	size     int64
	depth    int
}

// A session verifies each reachable object's actual bytes once, then releases its cache.
// Limits apply both to unique physical data and expanded logical text.
type Session struct {
	store       *Store
	objects     map[string]*object
	checkedDirs map[string]bool
	maxBytes    int64
	maxObjects  int
	Bytes       int64
}

func (s *Store) Session(maxBytes int64, maxObjects int) *Session {
	return &Session{
		store: s, objects: map[string]*object{},
		checkedDirs: map[string]bool{}, maxBytes: maxBytes, maxObjects: maxObjects,
	}
}

func (s *Session) load(ref Ref, limit int64, depth int) (*object, error) {
	if ref.Bytes < 0 {
		return nil, fault.New(fault.StorageCorrupt, "negative object length")
	}
	if ref.Bytes > limit || depth > maxDepth {
		return nil, fault.New(fault.LimitExceeded, "object logical capacity or depth exceeded")
	}
	if found := s.objects[ref.Hash]; found != nil {
		if found.size != ref.Bytes {
			return nil, fault.New(fault.StorageCorrupt, "object size mismatch")
		}
		if depth+found.depth > maxDepth {
			return nil, fault.New(fault.LimitExceeded, "object depth exceeded")
		}
		return found, nil
	}
	if len(s.objects) >= s.maxObjects {
		return nil, fault.New(fault.LimitExceeded, "object count exceeded")
	}
	data, err := s.store.readInSession(ref.Hash, s.checkedDirs, s.maxBytes-s.Bytes)
	if err != nil {
		return nil, err
	}
	if int64(len(data)) > s.maxBytes-s.Bytes {
		return nil, fault.New(fault.LimitExceeded, "object history capacity exceeded")
	}
	s.Bytes += int64(len(data))
	result := &object{kind: data[len(magic)], payload: data[len(magic)+1:]}
	switch result.kind {
	case textKind:
		if len(result.payload) > MaxChunk || !utf8.Valid(result.payload) {
			return nil, fault.New(fault.StorageCorrupt, "invalid UTF-8 leaf")
		}
		result.size = int64(len(result.payload))
	case notesKind:
		result.size = int64(len(result.payload))
	case branchKind:
		if len(result.payload) == 0 {
			return nil, fault.New(fault.StorageCorrupt, "empty branch")
		}
		count := int(result.payload[0])
		if count < 2 || count > Fanout || len(result.payload) != 1+count*40 {
			return nil, fault.New(fault.StorageCorrupt, "invalid branch encoding")
		}
		for i := 0; i < count; i++ {
			offset := 1 + i*40
			size := binary.BigEndian.Uint64(result.payload[offset+32 : offset+40])
			if size == 0 || size > uint64(limit-result.size) {
				return nil, fault.New(fault.StorageCorrupt, "branch size exceeded")
			}
			child := Ref{Hash: hex.EncodeToString(result.payload[offset : offset+32]), Bytes: int64(size)}
			node, err := s.load(child, limit, depth+1)
			if err != nil {
				return nil, err
			}
			if node.kind == notesKind {
				return nil, fault.New(fault.StorageCorrupt, "notes cannot be a text child")
			}
			result.children = append(result.children, child)
			result.size += child.Bytes
			result.depth = max(result.depth, node.depth+1)
		}
	default:
		return nil, fault.New(fault.UnsupportedStorage, "unknown object kind")
	}
	if result.size != ref.Bytes {
		return nil, fault.New(fault.StorageCorrupt, "object size mismatch")
	}
	// Children also consume slots; check again after their traversal.
	if len(s.objects) >= s.maxObjects {
		return nil, fault.New(fault.LimitExceeded, "object count exceeded")
	}
	s.objects[ref.Hash] = result
	return result, nil
}

func (s *Session) VerifyText(ref Ref, limit int64) error {
	node, err := s.load(ref, limit, 0)
	if err != nil {
		return err
	}
	if node.kind == notesKind {
		return fault.New(fault.StorageCorrupt, "expected text root")
	}
	return nil
}
func (s *Session) VerifyNotes(ref Ref, limit int64) error {
	node, err := s.load(ref, limit, 0)
	if err != nil {
		return err
	}
	if node.kind != notesKind {
		return fault.New(fault.StorageCorrupt, "expected notes blob")
	}
	return nil
}
func (s *Session) Hashes() []string {
	hashes := make([]string, 0, len(s.objects))
	for hash := range s.objects {
		hashes = append(hashes, hash)
	}
	sort.Strings(hashes)
	return hashes
}
func (s *Session) Notes(ref Ref, limit int64) ([]byte, error) {
	node, err := s.load(ref, limit, 0)
	if err != nil {
		return nil, err
	}
	if node.kind != notesKind {
		return nil, fault.New(fault.StorageCorrupt, "expected notes blob")
	}
	return append([]byte(nil), node.payload...), nil
}

func (s *Session) Text(ref Ref, limit int64) (string, error) {
	if err := s.VerifyText(ref, limit); err != nil {
		return "", err
	}
	var out strings.Builder
	out.Grow(int(ref.Bytes))
	var appendNode func(Ref)
	appendNode = func(current Ref) {
		node := s.objects[current.Hash]
		if node.kind == textKind {
			out.Write(node.payload)
			return
		}
		for _, child := range node.children {
			appendNode(child)
		}
	}
	appendNode(ref)
	return out.String(), nil
}
