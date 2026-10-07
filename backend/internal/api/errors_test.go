package api

import (
	"encoding/json"
	"fmt"
	"io/fs"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"unicode"

	"github.com/bnggbn/Pageforge-Native/backend/internal/config"
	"github.com/bnggbn/Pageforge-Native/backend/internal/fault"
	"github.com/bnggbn/Pageforge-Native/backend/internal/library"
	"github.com/bnggbn/Pageforge-Native/backend/internal/vax"
)

func assertErrorResponse(t *testing.T, w *httptest.ResponseRecorder, status int, code fault.Code) {
	t.Helper()
	var result errorResponse
	if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil {
		t.Fatalf("error is not JSON: %s: %v", w.Body.String(), err)
	}
	if w.Code != status || result.Code != code || result.Error == "" ||
		w.Header().Get("Content-Type") != "application/json; charset=utf-8" {
		t.Fatalf("error contract: status %d, body %s", w.Code, w.Body.String())
	}
}

func TestHTTPErrorMappingKeepsDependencyAbsenceOutOf404(t *testing.T) {
	cause := &fs.PathError{Op: "open", Path: "private/library/object", Err: fs.ErrNotExist}
	for _, test := range []struct {
		err    error
		status int
		code   fault.Code
	}{
		{fault.Read(cause), 500, fault.StorageMissing},
		{fmt.Errorf("version: %w", fault.New(fault.StorageCorrupt, "raw hash mismatch")), 500, fault.StorageCorrupt},
		{fault.Write(cause), 500, fault.StorageIO},
		{fault.New(fault.LimitExceeded, "超過容量"), 413, fault.LimitExceeded},
		{fault.New(fault.UnsafePath, "不允許連結"), 400, fault.UnsafePath},
		{fault.New(fault.UnsupportedStorage, "unknown root"), 500, fault.UnsupportedStorage},
		{fmt.Errorf("wrapped: %w", library.ErrConflict), 409, fault.Conflict},
		{fault.Wrap(fault.NotFound, "missing document", cause), 404, fault.NotFound},
	} {
		w := httptest.NewRecorder()
		respond(w, nil, test.err)
		assertErrorResponse(t, w, test.status, test.code)
		if strings.Contains(w.Body.String(), cause.Path) || strings.Contains(w.Body.String(), "raw hash") {
			t.Fatal("internal storage diagnostic leaked")
		}
		if strings.IndexFunc(w.Body.String(), func(r rune) bool { return unicode.Is(unicode.Han, r) }) >= 0 {
			t.Fatal("HTTP error localization belongs to the client")
		}
	}
}

func TestErrorContractAcrossAuthenticationRoutingAndRequestDecoding(t *testing.T) {
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
	app.Config.Limits.RequestMiB = 1
	for _, test := range []struct {
		name, method, path, body string
		auth                     bool
		status                   int
		code                     fault.Code
	}{
		{"auth", "GET", "/v1/books", "", false, 401, fault.Unauthorized},
		{"host", "GET", "/v1/books", "", true, 403, fault.Forbidden},
		{"route", "GET", "/v1/unknown", "", true, 404, fault.NotFound},
		{"method", "POST", "/v1/books", "{}", true, 405, fault.MethodNotAllowed},
		{"json", "POST", "/v1/import", "{", true, 400, fault.InvalidRequest},
		{"trailing", "POST", "/v1/import", "{} {}", true, 400, fault.InvalidRequest},
		{"base64", "POST", "/v1/import", `{"filename":"a.txt","source":"!!!"}`, true, 400, fault.InvalidRequest},
		{"request-limit", "POST", "/v1/import", strings.Repeat(" ", 1024*1024) + "{}", true, 413, fault.LimitExceeded},
		{"resource", "GET", "/v1/books/" + vax.UUID(), "", true, 404, fault.NotFound},
	} {
		t.Run(test.name, func(t *testing.T) {
			r := httptest.NewRequest(test.method, "http://127.0.0.1:12345"+test.path, strings.NewReader(test.body))
			if test.auth {
				r.Header.Set("Authorization", "Bearer "+app.Token)
			}
			if test.name == "host" {
				r.Host = "example.com"
			}
			w := httptest.NewRecorder()
			app.Handler().ServeHTTP(w, r)
			assertErrorResponse(t, w, test.status, test.code)
			if test.name == "method" && !strings.Contains(w.Header().Get("Allow"), "GET") {
				t.Fatal("ServeMux Allow header lost")
			}
		})
	}
}

func TestObjectBookErrorsCarryCodesThroughWarmAPIReads(t *testing.T) {
	for _, kind := range []string{"missing", "corrupt", "unsupported", "limit", "vax", "missing-manifest", "malformed-manifest", "missing-library-directory"} {
		t.Run(kind, func(t *testing.T) {
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
			id, _, err := store.Import("codes.txt", []byte("內容與線索🌿"))
			if err != nil {
				t.Fatal(err)
			}
			book, err := store.LoadHistory(id)
			if err != nil {
				t.Fatal(err)
			}
			folder := filepath.Join(c.Paths.LibraryRoot, "books", id)
			catalog := filepath.Join(folder, "objects", "catalog.pfca")
			status, code := 500, fault.StorageCorrupt
			switch kind {
			case "missing-library-directory":
				err = os.Rename(filepath.Dir(folder), filepath.Join(c.Paths.LibraryRoot, "moved-books"))
				code = fault.StorageMissing
			case "missing":
				err = os.Remove(catalog)
				code = fault.StorageMissing
			case "malformed-manifest":
				err = os.WriteFile(filepath.Join(folder, "manifest.json"), []byte("{"), 0600)
			case "missing-manifest":
				err = os.Remove(filepath.Join(folder, "manifest.json"))
				code = fault.StorageMissing
			case "corrupt":
				data, readErr := os.ReadFile(catalog)
				if readErr != nil {
					t.Fatal(readErr)
				}
				data[len(data)-1] ^= 1
				err = os.WriteFile(catalog, data, 0600)
			default:
				file := filepath.Join(folder, "versions", book.Revisions[0].ID+".json")
				data, readErr := os.ReadFile(file)
				if readErr != nil {
					t.Fatal(readErr)
				}
				var record map[string]any
				if err = json.Unmarshal(data, &record); err != nil {
					t.Fatal(err)
				}
				switch kind {
				case "unsupported":
					record["storageVersion"] = 2
					code = fault.UnsupportedStorage
				case "limit":
					record["contentRoot"].(map[string]any)["bytes"] = c.Limits.TextMiB*1024*1024 + 1
					status, code = 413, fault.LimitExceeded
				case "vax":
					record["revision"].(map[string]any)["sai"] = "tampered"
				}
				data, err = json.Marshal(record)
				if err == nil {
					err = os.WriteFile(file, data, 0600)
				}
			}
			if err != nil {
				t.Fatal(err)
			}
			app := New(store, c, func() {})
			route := "http://127.0.0.1:12345/v1/books/" + id
			if kind == "missing-library-directory" {
				route = "http://127.0.0.1:12345/v1/books"
			}
			r := httptest.NewRequest("GET", route, nil)
			r.Header.Set("Authorization", "Bearer "+app.Token)
			w := httptest.NewRecorder()
			app.Handler().ServeHTTP(w, r)
			assertErrorResponse(t, w, status, code)
			if strings.Contains(w.Body.String(), c.Paths.LibraryRoot) {
				t.Fatal("private path leaked in storage failure")
			}
		})
	}
}
