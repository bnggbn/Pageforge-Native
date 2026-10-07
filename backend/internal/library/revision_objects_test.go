package library

import (
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/bnggbn/Pageforge-Native/backend/internal/model"
	"github.com/bnggbn/Pageforge-Native/backend/internal/vax"
)

func objectFixture(t *testing.T) (*Store, string, model.Book) {
	t.Helper()
	s := testStore(t)
	s.config.Storage.RevisionFormat = objectRevisionFormat
	id, _, err := s.Import("objects.md", []byte(strings.Repeat("# 原文🌿\n\n證據與想法。\n", 2000)))
	if err != nil {
		t.Fatal(err)
	}
	book, err := s.LoadHistory(id)
	if err != nil {
		t.Fatal(err)
	}
	return s, id, book
}
func objectRecord(t *testing.T, s *Store, id, revision string) objectRevision {
	t.Helper()
	file := filepath.Join(s.root, "books", id, "versions", revision+".json")
	data, err := os.ReadFile(file)
	if err != nil {
		t.Fatal(err)
	}
	record, err := decodeObjectRevision(data, revision)
	if err != nil {
		t.Fatal(err)
	}
	return record
}

func TestObjectVersionsShareTextAndPreserveVAX(t *testing.T) {
	s, id, book := objectFixture(t)
	head := book.Revisions[0]
	folder := filepath.Join(s.root, "books", id)
	original, _ := os.ReadFile(filepath.Join(folder, "original.md"))
	firstFile := filepath.Join(folder, "versions", head.ID+".json")
	firstBytes, _ := os.ReadFile(firstFile)
	first := objectRecord(t, s, id, head.ID)
	notes := []model.Note{{ID: vax.UUID(), Body: "自己的線索", Quote: "證據", Location: "全文筆記", CreatedAt: vax.Now()}}
	book, err := s.CommitHistory(id, Commit{ExpectedHead: head.ID, Kind: "note", Content: head.Content, Notes: notes})
	if err != nil {
		t.Fatal(err)
	}
	withNote := book.Revisions[1]
	second := objectRecord(t, s, id, withNote.ID)
	if second.ContentRoot != first.ContentRoot || second.NotesRoot == first.NotesRoot {
		t.Fatal("note version did not share text")
	}
	book, err = s.CommitHistory(id, Commit{ExpectedHead: withNote.ID, Kind: "edit", Content: "前言\n" + head.Content})
	if err != nil {
		t.Fatal(err)
	}
	third := objectRecord(t, s, id, book.Revisions[2].ID)
	if third.NotesRoot != second.NotesRoot {
		t.Fatal("edit duplicated unchanged notes")
	}
	book, err = s.CommitHistory(id, Commit{ExpectedHead: book.Revisions[2].ID, Kind: "restore", RestoredFrom: &withNote.ID})
	if err != nil {
		t.Fatal(err)
	}
	fourth := objectRecord(t, s, id, book.Revisions[3].ID)
	if fourth.ContentRoot != second.ContentRoot || fourth.NotesRoot != second.NotesRoot {
		t.Fatal("restore did not reuse objects")
	}
	if err = vax.Verify(book.Document, original, book.Revisions); err != nil {
		t.Fatal("legacy VAX changed", err)
	}
	after, _ := os.ReadFile(firstFile)
	if string(after) != string(firstBytes) {
		t.Fatal("immutable first revision rewritten")
	}
	sourceAfter, _ := os.ReadFile(filepath.Join(folder, "original.md"))
	if string(sourceAfter) != string(original) {
		t.Fatal("source rewritten")
	}
	book.Revisions[1].Notes[0].Body = "caller mutation"
	if book.Revisions[2].Notes[0].Body != "自己的線索" {
		t.Fatal("note slices alias different versions")
	}
	again, err := s.LoadHistory(id)
	if err != nil || again.Revisions[1].Notes[0].Body != "自己的線索" {
		t.Fatal("cache caller alias", err)
	}
	wall := model.EvidenceWall{SchemaVersion: 1, Cards: []model.EvidenceCard{{NoteID: notes[0].ID, X: 40, Y: 40}}, Edges: []model.EvidenceEdge{}}
	if _, err = s.SaveEvidence(id, SaveEvidence{Wall: wall, ExpectedHead: again.Revisions[3].ID}); err != nil {
		t.Fatal("layout could not resolve object notes", err)
	}
	if err = s.Close(); err != nil {
		t.Fatal(err)
	}
	s.config.Storage.RevisionFormat = "legacy"
	reopened, err := Open(s.config)
	if err != nil {
		t.Fatal(err)
	}
	defer reopened.Close()
	recovered, err := reopened.LoadHistory(id)
	if err != nil || recovered.Revisions[3].Content != head.Content {
		t.Fatal("object reload with legacy default", err)
	}
	if _, err = reopened.CommitHistory(id, Commit{ExpectedHead: recovered.Revisions[3].ID, Kind: "edit", Content: "繼續寫"}); err != nil {
		t.Fatal(err)
	}
}

func TestObjectFormatDoesNotMigrateLegacyBook(t *testing.T) {
	s := testStore(t)
	id, _, err := s.Import("legacy.txt", []byte("original"))
	if err != nil {
		t.Fatal(err)
	}
	book, err := s.LoadHistory(id)
	if err != nil {
		t.Fatal(err)
	}
	s.config.Storage.RevisionFormat = objectRevisionFormat
	updated, err := s.CommitHistory(id, Commit{ExpectedHead: book.Revisions[0].ID, Kind: "edit", Content: "next"})
	if err != nil {
		t.Fatal(err)
	}
	m, err := s.manifest(id)
	if err != nil || m.RevisionStorage != "" {
		t.Fatal("legacy marker changed", err)
	}
	var record model.Revision
	if err = readJSON(filepath.Join(s.root, "books", id, "versions", updated.Revisions[1].ID+".json"), &record); err != nil || record.Content != "next" {
		t.Fatal("legacy representation changed", err)
	}
}

func TestObjectCacheRejectsTamperingAndRootSubstitution(t *testing.T) {
	for _, mode := range []string{"bytes", "source", "root", "missing", "count", "expanded"} {
		t.Run(mode, func(t *testing.T) {
			s, id, book := objectFixture(t)
			head := book.Revisions[0]
			record := objectRecord(t, s, id, head.ID)
			objects, err := s.objectStore(filepath.Join(s.root, "books", id))
			if err != nil {
				t.Fatal(err)
			}
			switch mode {
			case "bytes":
				mutateObject(t, s, id, record.ContentRoot.Hash, false)
				before, _ := os.ReadFile(filepath.Join(s.root, "books", id, "manifest.json"))
				if _, err = s.CommitHistory(id, Commit{ExpectedHead: head.ID, Kind: "edit", Content: "replacement"}); err == nil {
					t.Fatal("corrupt dependency committed")
				}
				after, _ := os.ReadFile(filepath.Join(s.root, "books", id, "manifest.json"))
				if string(before) != string(after) {
					t.Fatal("head moved on failure")
				}
			case "source":
				file := filepath.Join(s.root, "books", id, "original.md")
				info, _ := os.Stat(file)
				bytes, _ := os.ReadFile(file)
				bytes[0] = 'x'
				if err = os.WriteFile(file, bytes, 0600); err != nil {
					t.Fatal(err)
				}
				if err = os.Chtimes(file, info.ModTime(), info.ModTime()); err != nil {
					t.Fatal(err)
				}
			case "root":
				record.ContentRoot, err = objects.PutText("different valid object")
				if err != nil {
					t.Fatal(err)
				}
				if err = objects.Flush(); err != nil {
					t.Fatal(err)
				}
				bytes, _ := json.Marshal(record)
				if err = os.WriteFile(filepath.Join(s.root, "books", id, "versions", head.ID+".json"), bytes, 0600); err != nil {
					t.Fatal(err)
				}
			case "missing":
				mutateObject(t, s, id, record.ContentRoot.Hash, true)
			case "count":
				s.config.Storage.ObjectCount = 1
			case "expanded":
				s.cache = nil
				s.config.Storage.HistoryMiB = 0
			}
			if _, err = s.LoadHistory(id); err == nil {
				t.Fatal("invalid dependency passed warm verification")
			}
		})
	}
}

func TestObjectAdmissionKeepsHeadAndRejectsUnreadableImports(t *testing.T) {
	s := testStore(t)
	s.config.Storage.RevisionFormat = objectRevisionFormat
	s.config.Storage.ObjectCount = 1
	if _, _, err := s.Import("too-many.txt", []byte("valid text")); err == nil {
		t.Fatal("unreadable import published")
	}
	list, err := s.List()
	if err != nil || len(list) != 0 {
		t.Fatal("failed import visible", err)
	}
	s.config.Storage.ObjectCount = 100000
	id, _, err := s.Import("small.txt", []byte("valid text"))
	if err != nil {
		t.Fatal(err)
	}
	book, err := s.LoadHistory(id)
	if err != nil {
		t.Fatal(err)
	}
	head := book.Revisions[0]
	record := objectRecord(t, s, id, head.ID)
	objects, err := s.objectStore(filepath.Join(s.root, "books", id))
	if err != nil {
		t.Fatal(err)
	}
	session := objects.Session(1024*1024, 1000)
	if err = session.VerifyText(record.ContentRoot, 1024*1024); err != nil {
		t.Fatal(err)
	}
	if err = session.VerifyNotes(record.NotesRoot, 1024*1024); err != nil {
		t.Fatal(err)
	}
	s.config.Storage.ObjectCount = len(session.Hashes())
	before, _ := os.ReadFile(filepath.Join(s.root, "books", id, "manifest.json"))
	notes := []model.Note{{ID: vax.UUID(), Body: "new note", Location: "all", CreatedAt: vax.Now()}}
	if _, err = s.CommitHistory(id, Commit{ExpectedHead: head.ID, Kind: "note", Content: head.Content, Notes: notes}); err == nil {
		t.Fatal("over-budget head published")
	}
	after, _ := os.ReadFile(filepath.Join(s.root, "books", id, "manifest.json"))
	if string(before) != string(after) {
		t.Fatal("head changed on admission failure")
	}
	if _, err = s.LoadHistory(id); err != nil {
		t.Fatal("old head no longer readable", err)
	}
}

func TestObjectVersionDirectoryRejectsLink(t *testing.T) {
	s, id, _ := objectFixture(t)
	original := filepath.Join(s.root, "books", id, "versions")
	relocated := filepath.Join(s.root, "relocated-versions")
	if err := os.Rename(original, relocated); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(relocated, original); err != nil {
		if restoreErr := os.Rename(relocated, original); restoreErr != nil {
			t.Fatal(restoreErr)
		}
		t.Skip("symlink creation unavailable", err)
	}
	if _, err := s.LoadHistory(id); err == nil {
		t.Fatal("linked versions directory accepted")
	}
}

func mutateObject(t *testing.T, s *Store, id, hash string, remove bool) {
	t.Helper()
	folder := filepath.Join(s.root, "books", id, "objects")
	catalog := filepath.Join(folder, "catalog.pfca")
	data, err := os.ReadFile(catalog)
	if err == nil {
		count := binary.BigEndian.Uint32(data[5:9])
		cursor := 9
		for range count {
			entry := cursor
			name := hex.EncodeToString(data[cursor : cursor+32])
			size := int(binary.BigEndian.Uint32(data[cursor+32 : cursor+36]))
			cursor += 36
			if name == hash {
				if remove {
					data = append(data[:entry], data[cursor+size:]...)
					binary.BigEndian.PutUint32(data[5:9], count-1)
				} else {
					data[cursor+size-1] ^= 1
				}
				info, _ := os.Stat(catalog)
				if err = os.WriteFile(catalog, data, 0600); err != nil {
					t.Fatal(err)
				}
				if err = os.Chtimes(catalog, info.ModTime(), info.ModTime()); err != nil {
					t.Fatal(err)
				}
				return
			}
			cursor += size
		}
	} else if !os.IsNotExist(err) {
		t.Fatal(err)
	}
	file := filepath.Join(folder, hash[:2], hash+".pfo")
	if remove {
		if err = os.Remove(file); err != nil {
			t.Fatal(err)
		}
		return
	}
	info, _ := os.Stat(file)
	data, err = os.ReadFile(file)
	if err != nil {
		t.Fatal(err)
	}
	data[len(data)-1] ^= 1
	if err = os.WriteFile(file, data, 0600); err != nil {
		t.Fatal(err)
	}
	if err = os.Chtimes(file, info.ModTime(), info.ModTime()); err != nil {
		t.Fatal(err)
	}
}

func TestFailedObjectCommitDoesNotChargeUnreachableCatalogToOldHistory(t *testing.T) {
	s := testStore(t)
	s.config.Storage.RevisionFormat = objectRevisionFormat
	s.config.Storage.RecordMiB = 1
	s.config.Storage.HistoryMiB = 1
	source := benchmarkObjectText(100000)
	id, _, err := s.Import("budget.txt", []byte(source))
	if err != nil {
		t.Fatal(err)
	}
	book, err := s.LoadHistory(id)
	if err != nil {
		t.Fatal(err)
	}
	head := book.Revisions[0]
	file := filepath.Join(s.root, "books", id, "manifest.json")
	before, err := os.ReadFile(file)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = s.CommitHistory(id, Commit{
		ExpectedHead: head.ID, Kind: "edit", Content: benchmarkObjectText(900000),
	}); err == nil {
		t.Fatal("over-capacity candidate accepted")
	}
	after, err := os.ReadFile(file)
	if err != nil || string(before) != string(after) {
		t.Fatal("failed candidate changed head", err)
	}
	catalog := filepath.Join(s.root, "books", id, "objects", "catalog.pfca")
	info, err := os.Stat(catalog)
	if err != nil || info.Size() <= 1024*1024 {
		t.Fatal("fixture did not leave large unreferenced catalog", err)
	}
	for _, cold := range []bool{false, true} {
		if cold {
			s.cache = nil
		}
		loaded, err := s.LoadHistory(id)
		if err != nil || len(loaded.Revisions) != 1 || loaded.Revisions[0].Content != source {
			t.Fatal("old head unreadable after failed commit", cold, err)
		}
	}
}
