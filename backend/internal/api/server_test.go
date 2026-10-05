package api

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"

	"github.com/bnggbn/Pageforge-Native/backend/internal/config"
	"github.com/bnggbn/Pageforge-Native/backend/internal/library"
)

func TestAuthenticatedNativeWorkflow(t *testing.T) {
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
	app := New(store, c, func() {})
	server := httptest.NewServer(app.Handler())
	defer server.Close()
	request := func(method, path string, body any, token bool) *http.Response {
		t.Helper()
		data, _ := json.Marshal(body)
		r, _ := http.NewRequest(method, server.URL+path, bytes.NewReader(data))
		if token {
			r.Header.Set("Authorization", "Bearer "+app.Token)
		}
		response, err := server.Client().Do(r)
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { response.Body.Close() })
		return response
	}
	if r := request("GET", "/v1/books", nil, false); r.StatusCode != 401 {
		t.Fatal("missing token accepted")
	}
	r := request("POST", "/v1/import", map[string]string{"filename": "本機.md", "source": base64.StdEncoding.EncodeToString([]byte("# 原生閱讀🌿\n"))}, true)
	if r.StatusCode != 200 {
		t.Fatalf("import status %d", r.StatusCode)
	}
	var imported map[string]any
	json.NewDecoder(r.Body).Decode(&imported)
	id := imported["id"].(string)
	r = request("GET", "/v1/books/"+id, nil, true)
	var book map[string]any
	json.NewDecoder(r.Body).Decode(&book)
	revisions := book["revisions"].([]any)
	head := revisions[0].(map[string]any)["id"].(string)
	r = request("POST", "/v1/books/"+id+"/versions", map[string]any{"expectedHead": head, "kind": "edit", "content": "# 新版✨\n", "notes": []any{}, "restoredFrom": nil}, true)
	if r.StatusCode != 200 {
		t.Fatalf("commit status %d", r.StatusCode)
	}
	r = request("POST", "/v1/books/"+id+"/versions", map[string]any{"expectedHead": head, "kind": "edit", "content": "過期"}, true)
	if r.StatusCode != 409 {
		t.Fatal("HTTP stale head not rejected")
	}
	r = request("GET", "/v1/books/../private", nil, true)
	if r.StatusCode == 200 {
		t.Fatal("invalid path accepted")
	}
}
