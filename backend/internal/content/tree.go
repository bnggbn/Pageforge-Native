package content

import (
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"unicode/utf8"
)

// The fixed table and algorithm are part of PFCO version 1, not runtime configuration.
var gear = func() [256]uint64 {
	var table [256]uint64
	state := uint64(0x70616765666f7267)
	for i := range table {
		state += 0x9e3779b97f4a7c15
		value := state
		value = (value ^ (value >> 30)) * 0xbf58476d1ce4e5b9
		value = (value ^ (value >> 27)) * 0x94d049bb133111eb
		table[i] = value ^ (value >> 31)
	}
	return table
}()

// PutText scans the supplied text. Stable content boundaries reduce shifted-chunk rewrites,
// but this full-text API does not promise logarithmic edit processing.
func (s *Store) PutText(text string) (Ref, error) {
	if !utf8.ValidString(text) {
		return Ref{}, fmt.Errorf("text must be UTF-8")
	}
	leaves := []Ref{}
	start, cursor := 0, 0
	var rolling uint64
	for cursor < len(text) {
		_, width := utf8.DecodeRuneInString(text[cursor:])
		if cursor-start+width > MaxChunk {
			ref, err := s.put(textKind, []byte(text[start:cursor]), int64(cursor-start))
			if err != nil {
				return Ref{}, err
			}
			leaves = append(leaves, ref)
			start, rolling = cursor, 0
		}
		for i := 0; i < width; i++ {
			rolling = (rolling << 1) + gear[text[cursor+i]]
		}
		cursor += width
		if cursor-start >= MinChunk && (rolling&32767 == 0 || cursor-start == MaxChunk) {
			ref, err := s.put(textKind, []byte(text[start:cursor]), int64(cursor-start))
			if err != nil {
				return Ref{}, err
			}
			leaves = append(leaves, ref)
			start, rolling = cursor, 0
		}
	}
	if start < len(text) || len(leaves) == 0 {
		ref, err := s.put(textKind, []byte(text[start:]), int64(len(text)-start))
		if err != nil {
			return Ref{}, err
		}
		leaves = append(leaves, ref)
	}
	for len(leaves) > 1 {
		parents := []Ref{}
		for start := 0; start < len(leaves); start += Fanout {
			end := min(start+Fanout, len(leaves))
			if end-start == 1 {
				parents = append(parents, leaves[start])
				continue
			}
			data := make([]byte, 1+(end-start)*40)
			data[0] = byte(end - start)
			var size int64
			for i, child := range leaves[start:end] {
				hash, _ := hex.DecodeString(child.Hash)
				copy(data[1+i*40:], hash)
				binary.BigEndian.PutUint64(data[33+i*40:], uint64(child.Bytes))
				size += child.Bytes
			}
			ref, err := s.put(branchKind, data, size)
			if err != nil {
				return Ref{}, err
			}
			parents = append(parents, ref)
		}
		leaves = parents
	}
	return leaves[0], nil
}
