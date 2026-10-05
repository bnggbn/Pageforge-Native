package api

import (
	"bytes"
	"encoding/json"
	"github.com/bnggbn/Pageforge-Native/backend/internal/config"
	"github.com/bnggbn/Pageforge-Native/backend/internal/design"
	"github.com/bnggbn/Pageforge-Native/backend/internal/library"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func TestDesignAPIValidationAndConflicts(t *testing.T) {
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
	root := t.TempDir()
	data, err := os.ReadFile(filepath.Join("..", "..", "..", "pageforge.design.json"))
	if err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(filepath.Join(root, "pageforge.design.json"), data, 0600); err != nil {
		t.Fatal(err)
	}
	app := New(store, c, func() {})
	app.Design = design.New(root)
	server := httptest.NewServer(app.Handler())
	defer server.Close()
	request := func(method string, body any, auth, origin bool) (int, []byte) {
		t.Helper()
		data, _ := json.Marshal(body)
		r, _ := http.NewRequest(method, server.URL+"/v1/design", bytes.NewReader(data))
		if auth {
			r.Header.Set("Authorization", "Bearer "+app.Token)
		}
		if origin {
			r.Header.Set("Origin", "http://example.com")
		}
		response, err := server.Client().Do(r)
		if err != nil {
			t.Fatal(err)
		}
		defer response.Body.Close()
		result, _ := io.ReadAll(response.Body)
		return response.StatusCode, result
	}
	if status, _ := request("GET", nil, false, false); status != 401 {
		t.Fatal("unauthenticated design read accepted")
	}
	if status, _ := request("GET", nil, true, true); status != 401 {
		t.Fatal("browser origin design read accepted")
	}
	status, data := request("GET", nil, true, false)
	if status != 200 {
		t.Fatalf("GET status %d", status)
	}
	var snapshot design.Snapshot
	if err = json.Unmarshal(data, &snapshot); err != nil {
		t.Fatal(err)
	}
	changed := snapshot.Document
	changed.Reader.LineHeight = 2.2
	if status, _ = request("PUT", map[string]any{"document": changed, "expectedRevision": snapshot.Revision}, true, false); status != 200 {
		t.Fatalf("PUT status %d", status)
	}
	if status, _ = request("PUT", map[string]any{"document": snapshot.Document, "expectedRevision": snapshot.Revision}, true, false); status != 409 {
		t.Fatal("stale design accepted")
	}
	_, data = request("GET", nil, true, false)
	json.Unmarshal(data, &snapshot)
	changed.Reader.PageWidth = 999999
	if status, _ = request("PUT", map[string]any{"document": changed, "expectedRevision": snapshot.Revision}, true, false); status != 400 {
		t.Fatal("invalid bounds accepted")
	}
	var extra map[string]any
	data, _ = json.Marshal(snapshot.Document)
	json.Unmarshal(data, &extra)
	extra["script"] = "run()"
	if status, _ = request("PUT", map[string]any{"document": extra, "expectedRevision": snapshot.Revision}, true, false); status != 400 {
		t.Fatal("unknown field accepted")
	}
	final, err := app.Design.Load()
	if err != nil || final != snapshot {
		t.Fatal("rejected request changed design", err)
	}
}
