package library

import (
	"path/filepath"
	"testing"

	"github.com/bnggbn/Pageforge-Native/backend/internal/config"
	"github.com/bnggbn/Pageforge-Native/backend/internal/model"
	"github.com/bnggbn/Pageforge-Native/backend/internal/vax"
)

// 1M runes, 100 revisions. Fixtures publish valid immutable versions directly;
// preparation is outside timing and does not measure normal Commit latency.
func BenchmarkReaderSnapshotWorkloads(b *testing.B) {
	for _, workload := range []string{"distinct_edits", "accumulating_notes"} {
		b.Run(workload, func(b *testing.B) {
			c, err := config.Load(filepath.Join("..", "..", ".."))
			if err != nil {
				b.Fatal(err)
			}
			c.Paths.LibraryRoot = b.TempDir()
			c.Storage.RevisionFormat = objectRevisionFormat
			s, err := Open(c)
			if err != nil {
				b.Fatal(err)
			}
			defer s.Close()
			source := benchmarkObjectText(1000000)
			id, _, err := s.Import("snapshot.txt", []byte(source))
			if err != nil {
				b.Fatal(err)
			}
			first, err := s.Load(id)
			if err != nil {
				b.Fatal(err)
			}
			previous := first.Revisions[0]
			m, err := s.manifest(id)
			if err != nil {
				b.Fatal(err)
			}
			folder := filepath.Join(s.root, "books", id)
			for i := 0; i < 99; i++ {
				kind, text, notes := "edit", source, previous.Notes
				if workload == "distinct_edits" {
					at := (i * 12347) % len(source)
					for at > 0 && source[at]&0xc0 == 0x80 {
						at--
					}
					text = source[:at] + "changed sentence.\n" + source[at:]
				} else {
					kind = "note"
					notes = append(append([]model.Note{}, notes...), model.Note{
						ID: vax.UUID(), Body: "A thought about the cited passage and its relation to the rest.",
						Quote:    "A quoted passage with context, rather than repeatedly updating the same note from an earlier version.",
						Location: "全文筆記", CreatedAt: vax.Now(),
					})
				}
				r, err := vax.Create(m.Document, &previous, kind, text, notes, nil)
				if err != nil {
					b.Fatal(err)
				}
				if err = s.writeRevision(folder, m.RevisionStorage, r); err != nil {
					b.Fatal(err)
				}
				m.RevisionIDs = append(m.RevisionIDs, r.ID)
				m.Document.UpdatedAt = r.CreatedAt
				previous = r
			}
			if err = atomicJSON(filepath.Join(folder, "manifest.json"), m); err != nil {
				b.Fatal(err)
			}
			for _, mode := range []string{"cold", "warm"} {
				b.Run(mode, func(b *testing.B) {
					if _, err := s.Load(id); err != nil {
						b.Fatal(err)
					}
					b.ReportAllocs()
					b.ResetTimer()
					for i := 0; i < b.N; i++ {
						if mode == "cold" {
							s.cache = nil
						}
						snapshot, err := s.Load(id)
						if err != nil || len(snapshot.Revisions) != 1 || snapshot.RevisionCount != 100 || snapshot.Revisions[0].ID != previous.ID {
							b.Fatal("snapshot", err)
						}
					}
				})
			}
		})
	}
}
