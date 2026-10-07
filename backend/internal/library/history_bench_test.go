package library

import (
	"fmt"
	"path/filepath"
	"strings"
	"testing"

	"github.com/bnggbn/Pageforge-Native/backend/internal/config"
	"github.com/bnggbn/Pageforge-Native/backend/internal/vax"
)

func BenchmarkWarmLoadHistory(b *testing.B) {
	for _, count := range []int{1, 100, 500} {
		b.Run(fmt.Sprintf("revisions_%d", count), func(b *testing.B) {
			c, err := config.Load(filepath.Join("..", "..", ".."))
			if err != nil {
				b.Fatal(err)
			}
			c.Storage.RevisionFormat = "legacy"
			c.Paths.LibraryRoot = b.TempDir()
			s, err := Open(c)
			if err != nil {
				b.Fatal(err)
			}
			defer s.Close()
			id, _, err := s.Import("review.txt", []byte(strings.Repeat("x", 65536)))
			if err != nil {
				b.Fatal(err)
			}
			book, err := s.LoadHistory(id)
			if err != nil {
				b.Fatal(err)
			}
			m, err := s.manifest(id)
			if err != nil {
				b.Fatal(err)
			}
			last := book.Revisions[0]
			for i := 1; i < count; i++ {
				next, err := vax.Create(book.Document, &last, "edit", last.Content, nil, nil)
				if err != nil {
					b.Fatal(err)
				}
				if err := atomicJSON(filepath.Join(s.root, "books", id, "versions", next.ID+".json"), next); err != nil {
					b.Fatal(err)
				}
				m.RevisionIDs = append(m.RevisionIDs, next.ID)
				last = next
			}
			if err := atomicJSON(filepath.Join(s.root, "books", id, "manifest.json"), m); err != nil {
				b.Fatal(err)
			}
			// Warm validation is outside the measured loop; every read still hashes current bytes.
			if _, err := s.LoadHistory(id); err != nil {
				b.Fatal(err)
			}
			b.ReportAllocs()
			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				loaded, err := s.LoadHistory(id)
				if err != nil || len(loaded.Revisions) != count {
					b.Fatalf("load failed: %v", err)
				}
			}
		})
	}
}
