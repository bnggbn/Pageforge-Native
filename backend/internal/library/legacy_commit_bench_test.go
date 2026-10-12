package library

import (
	"path/filepath"
	"testing"

	"github.com/bnggbn/Pageforge-Native/backend/internal/config"
	"github.com/bnggbn/Pageforge-Native/backend/internal/model"
	"github.com/bnggbn/Pageforge-Native/backend/internal/vax"
)

// Normal Commit latency, with verified-cache retention disabled. Preparation
// publishes valid synthetic history outside timing; the filesystem cache stays warm.
func BenchmarkLegacyCommitWithoutVerifiedCache(b *testing.B) {
	for _, workload := range []string{"first_edit", "accumulating_notes_30"} {
		b.Run(workload, func(b *testing.B) {
			c, err := config.Load(filepath.Join("..", "..", ".."))
			if err != nil {
				b.Fatal(err)
			}
			c.Paths.LibraryRoot = b.TempDir()
			c.Storage.RevisionFormat = ""
			c.Storage.VerifiedCacheMiB = 0
			s, err := Open(c)
			if err != nil {
				b.Fatal(err)
			}
			defer s.Close()
			source := benchmarkObjectText(1000000)
			id, _, err := s.Import("commit.txt", []byte(source))
			if err != nil {
				b.Fatal(err)
			}
			book, err := s.LoadHistory(id)
			if err != nil {
				b.Fatal(err)
			}
			previous := book.Revisions[0]
			manifest, err := s.manifest(id)
			if err != nil {
				b.Fatal(err)
			}
			folder := filepath.Join(s.root, "books", id)
			if workload == "accumulating_notes_30" {
				for i := 0; i < 30; i++ {
					notes := append(append([]model.Note{}, previous.Notes...), model.Note{
						ID: vax.UUID(), Body: "A thought about this passage.",
						Quote: "A quoted passage with context.", CreatedAt: vax.Now(),
					})
					revision, err := vax.Create(manifest.Document, &previous, "note", source, notes, nil)
					if err != nil {
						b.Fatal(err)
					}
					if err = s.writeRevision(folder, "", revision); err != nil {
						b.Fatal(err)
					}
					manifest.RevisionIDs = append(manifest.RevisionIDs, revision.ID)
					previous = revision
				}
				if err = atomicJSON(filepath.Join(folder, "manifest.json"), manifest); err != nil {
					b.Fatal(err)
				}
			}
			input := Commit{ExpectedHead: previous.ID, Kind: "edit", Content: source + "Changed sentence."}
			if workload == "accumulating_notes_30" {
				input.Kind = "note"
				input.Content = source
				input.Notes = append(append([]model.Note{}, previous.Notes...), model.Note{
					ID: vax.UUID(), Body: "Another thought.", Quote: "Another passage.", CreatedAt: vax.Now(),
				})
			}
			b.ReportAllocs()
			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				result, err := s.Commit(id, input)
				if err != nil {
					b.Fatal(err)
				}
				if len(result.Revisions) != 1 {
					b.Fatal("commit returned historical bodies")
				}
				b.StopTimer()
				// Restore only the synthetic manifest, keeping each sample's history equal.
				if err = atomicJSON(filepath.Join(folder, "manifest.json"), manifest); err != nil {
					b.Fatal(err)
				}
				s.cache = nil
				b.StartTimer()
			}
		})
	}
}
