package api

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/bnggbn/Pageforge-Native/backend/internal/config"
	"github.com/bnggbn/Pageforge-Native/backend/internal/library"
	"github.com/bnggbn/Pageforge-Native/backend/internal/settings"
)

func TestClientSettingsAPIKeepsStorageGuardsWithoutOwningUIFields(t *testing.T) {
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
	defaults := filepath.Join(root, "defaults.json")
	if err := os.WriteFile(defaults, []byte(`{"clientOwned":true}`), 0600); err != nil {
		t.Fatal(err)
	}
	app := New(store, c, func() {})
	app.ClientSettings = settings.New(defaults, filepath.Join(root, "local.json"), 16*1024)
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
		t.Fatal("unauthenticated read accepted")
	}
	if status, _ := request("GET", nil, true, true); status != 401 {
		t.Fatal("browser origin read accepted")
	}
	status, data := request("GET", nil, true, false)
	if status != 200 {
		t.Fatalf("GET status %d", status)
	}
	var before settings.Snapshot
	if err := json.Unmarshal(data, &before); err != nil {
		t.Fatal(err)
	}
	// Unknown versions and UI fields are valid opaque storage, not valid Flutter themes.
	changed := json.RawMessage(`{"schemaVersion":42,"theme":{"headingFont":"future font"},"reader":{"pageWidth":999999},"extra":true}`)
	status, data = request("PUT", map[string]any{"document": changed, "expectedRevision": before.Revision}, true, false)
	if status != 200 {
		t.Fatalf("opaque PUT status %d: %s", status, data)
	}
	var saved settings.Snapshot
	if err := json.Unmarshal(data, &saved); err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(saved.Document, changed) {
		t.Fatal("storage rewrote UI fields")
	}
	if status, _ := request("PUT", map[string]any{"document": before.Document, "expectedRevision": before.Revision}, true, false); status != 409 {
		t.Fatal("stale write accepted")
	}
	for _, body := range []any{
		map[string]any{"document": nil, "expectedRevision": saved.Revision},
		map[string]any{"document": []any{}, "expectedRevision": saved.Revision},
		map[string]any{"document": map[string]any{"x": strings.Repeat("x", 16385)}, "expectedRevision": saved.Revision},
		map[string]any{"document": changed, "expectedRevision": saved.Revision, "filename": "arbitrary.json"},
	} {
		if status, _ := request("PUT", body, true, false); status != 400 && status != 413 {
			t.Fatal("invalid storage request accepted", status)
		}
	}
	final, err := app.ClientSettings.Load()
	if err != nil || final.Revision != saved.Revision || !bytes.Equal(final.Document, saved.Document) {
		t.Fatal("rejected request changed settings", err)
	}
	// A document exactly at the storage limit must fit with its HTTP wrapper.
	atLimit := json.RawMessage(`{"x":"` + strings.Repeat("x", 16384-len(`{"x":""}`)) + `"}`)
	if len(atLimit) != 16384 {
		t.Fatal("invalid limit fixture")
	}
	if status, _ := request("PUT", map[string]any{"document": atLimit, "expectedRevision": saved.Revision}, true, false); status != 200 {
		t.Fatal("valid document rejected due to wrapper overhead", status)
	}
}
