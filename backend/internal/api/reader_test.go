package api

import (
	"encoding/json"
	"github.com/bnggbn/Pageforge-Native/backend/internal/config"
	"github.com/bnggbn/Pageforge-Native/backend/internal/library"
	"github.com/bnggbn/Pageforge-Native/backend/internal/model"
	"net/http/httptest"
	"path/filepath"
	"testing"
)

func TestReaderProjectionAndOldRevisionRetrieval(t *testing.T) {
	c, err := config.Load(filepath.Join("..", "..", ".."))
	if err != nil {
		t.Fatal(err)
	}
	c.Paths.LibraryRoot = t.TempDir()
	store, err := library.Open(c)
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	id, _, _ := store.Import("reader.txt", []byte("original"))
	book, _ := store.Load(id)
	old := book.Revisions[0].ID
	book, err = store.Commit(id, library.Commit{ExpectedHead: old, Kind: "edit", Content: "changed", Notes: []model.Note{}})
	if err != nil {
		t.Fatal(err)
	}
	app := New(store, c, func() {})
	get := func(path string) *httptest.ResponseRecorder {
		r := httptest.NewRequest("GET", "http://127.0.0.1:12345"+path, nil)
		r.Header.Set("Authorization", "Bearer "+app.Token)
		w := httptest.NewRecorder()
		app.Handler().ServeHTTP(w, r)
		return w
	}
	compact := get("/v1/books/" + id + "?view=reader")
	var response struct {
		model.Book
		History       []revisionSummary
		RevisionCount int
	}
	if err := json.Unmarshal(compact.Body.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	if compact.Code != 200 || len(response.Revisions) != 1 || response.RevisionCount != 2 || len(response.History) != 2 || response.Revisions[0].Content != "changed" {
		t.Fatalf("compact projection %d: %s", compact.Code, compact.Body.String())
	}
	full := get("/v1/books/" + id)
	var legacy model.Book
	json.Unmarshal(full.Body.Bytes(), &legacy)
	if len(legacy.Revisions) != 2 {
		t.Fatal("legacy response lost history")
	}
	revision := get("/v1/books/" + id + "/versions/" + old)
	var snapshot model.Revision
	json.Unmarshal(revision.Body.Bytes(), &snapshot)
	if revision.Code != 200 || snapshot.Content != "original" {
		t.Fatal("old base not retrievable")
	}
	invalid := get("/v1/books/" + id + "/versions/not-in-this-book")
	if invalid.Code == 200 {
		t.Fatal("foreign revision accepted")
	}
}
