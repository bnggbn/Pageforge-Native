package library

import (
	"fmt"
	"math/rand"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/bnggbn/Pageforge-Native/backend/internal/config"
	"github.com/bnggbn/Pageforge-Native/backend/internal/model"
	"github.com/bnggbn/Pageforge-Native/backend/internal/vax"
)

func benchmarkObjectText(count int) string {
	random := rand.New(rand.NewSource(526))
	alphabet := []rune("abcdefghijklmnop0123456789文字章節🌿🧩\n ")
	var text strings.Builder
	for range count {
		text.WriteRune(alphabet[random.Intn(len(alphabet))])
	}
	return text.String()
}

// Same source, same number of versions and real VAX verification in both formats.
// Preparation writes valid revisions directly, excluding quadratic Commit setup time.
func BenchmarkObjectHistory(b *testing.B) {
	for _, shape := range []string{"notes", "prefix_edits"} {
		for _, format := range []string{"legacy", objectRevisionFormat} {
			b.Run(shape+"/"+format, func(b *testing.B) {
				c, err := config.Load(filepath.Join("..", "..", ".."))
				if err != nil {
					b.Fatal(err)
				}
				c.Paths.LibraryRoot = b.TempDir()
				c.Storage.RevisionFormat = format
				s, err := Open(c)
				if err != nil {
					b.Fatal(err)
				}
				defer s.Close()
				text := benchmarkObjectText(1000000)
				id, _, err := s.Import("benchmark.txt", []byte(text))
				if err != nil {
					b.Fatal(err)
				}
				book, err := s.Load(id)
				if err != nil {
					b.Fatal(err)
				}
				m, err := s.manifest(id)
				if err != nil {
					b.Fatal(err)
				}
				previous := book.Revisions[0]
				noteID := vax.UUID()
				folder := filepath.Join(s.root, "books", id)
				for i := 1; i < 40; i++ {
					kind, body, notes := "note", text, []model.Note{{ID: noteID, Body: fmt.Sprintf("線索 %d", i), Quote: "原文", Location: "全文筆記", CreatedAt: vax.Now()}}
					if shape == "prefix_edits" {
						kind = "edit"
						body = fmt.Sprintf("前言 %d\n", i) + text
						notes = []model.Note{}
					}
					next, err := vax.Create(book.Document, &previous, kind, body, notes, nil)
					if err != nil {
						b.Fatal(err)
					}
					if err = s.writeRevision(folder, m.RevisionStorage, next); err != nil {
						b.Fatal(err)
					}
					m.RevisionIDs = append(m.RevisionIDs, next.ID)
					previous = next
				}
				if err = atomicJSON(filepath.Join(folder, "manifest.json"), m); err != nil {
					b.Fatal(err)
				}
				var disk int64
				if err = filepath.WalkDir(folder, func(_ string, entry os.DirEntry, err error) error {
					if err != nil {
						return err
					}
					if !entry.IsDir() {
						info, err := entry.Info()
						if err != nil {
							return err
						}
						disk += info.Size()
					}
					return nil
				}); err != nil {
					b.Fatal(err)
				}
				for _, temperature := range []string{"cold", "repeat"} {
					b.Run(temperature, func(b *testing.B) {
						s.cache = nil
						if temperature == "repeat" {
							if _, err := s.Load(id); err != nil {
								b.Fatal(err)
							}
						}
						b.ReportAllocs()
						b.ResetTimer()
						for i := 0; i < b.N; i++ {
							if temperature == "cold" {
								s.cache = nil
							}
							loaded, err := s.Load(id)
							if err != nil || len(loaded.Revisions) != 40 {
								b.Fatal("load", err)
							}
						}
						b.StopTimer()
						b.ReportMetric(float64(disk)/(1024*1024), "disk-MiB")
					})
				}
			})
		}
	}
}
