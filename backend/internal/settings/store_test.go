package settings

import (
	"bytes"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"github.com/bnggbn/Pageforge-Native/backend/internal/fault"
)

func fixture(t *testing.T) ([]byte, *Store) {
	t.Helper()
	root := t.TempDir()
	defaults := filepath.Join(root, "defaults.json")
	data := []byte(`{ "schemaVersion": 7, "renderer": "future", "theme": {"accent": "token:new"} }`)
	if err := os.WriteFile(defaults, data, 0600); err != nil {
		t.Fatal(err)
	}
	return data, New(defaults, filepath.Join(root, "local.json"), 16*1024)
}

func TestOpaqueSaveReopenAndConflict(t *testing.T) {
	defaults, store := fixture(t)
	before, err := store.Load()
	if err != nil {
		t.Fatal(err)
	}
	next := json.RawMessage(`{"schemaVersion":99,"theme":{"unknown":{"values":[false,0,null,"中文🌿"]}},"script":"never executed"}`)
	saved, err := store.Save(next, before.Revision)
	if err != nil {
		t.Fatal(err)
	}
	next[0] = 'x'
	reopened, err := New(store.defaults, store.override, store.maxBytes).Load()
	if err != nil || reopened.Revision != saved.Revision || !bytes.Equal(reopened.Document, saved.Document) {
		t.Fatal("opaque settings did not round-trip", err)
	}
	if _, err = store.Save(before.Document, before.Revision); !errors.Is(err, ErrConflict) {
		t.Fatal("stale write accepted", err)
	}
	if data, err := os.ReadFile(store.defaults); err != nil || !bytes.Equal(data, defaults) {
		t.Fatal("defaults overwritten", err)
	}
	saved.Document[0] = 'x'
	final, err := store.Load()
	if err != nil || !bytes.Equal(final.Document, reopened.Document) {
		t.Fatal("snapshot aliases caller bytes", err)
	}
}

func TestInvalidOrOversizedWritesPreserveStoredBytes(t *testing.T) {
	_, store := fixture(t)
	before, err := store.Load()
	if err != nil {
		t.Fatal(err)
	}
	for _, data := range []string{"", "{", "{} {}", "null", `{"x":"` + string([]byte{0xff}) + `"}`, "[]", "42", `"string"`, strings.Repeat(" ", int(store.maxBytes)+1)} {
		_, err := store.Save(json.RawMessage(data), before.Revision)
		code, found := fault.CodeOf(err)
		if !found || (code != fault.InvalidRequest && code != fault.LimitExceeded) {
			t.Fatal("invalid write accepted or misclassified", data, err)
		}
		after, err := store.Load()
		if err != nil || after.Revision != before.Revision || !bytes.Equal(after.Document, before.Document) {
			t.Fatal("failed write altered stored settings", err)
		}
		if _, err := os.Stat(store.override); !os.IsNotExist(err) {
			t.Fatal("failed write created an override", err)
		}
	}
}

func TestConcurrentSavesKeepOneWinner(t *testing.T) {
	_, store := fixture(t)
	before, _ := store.Load()
	var wg sync.WaitGroup
	results := make(chan error, 2)
	for _, data := range []string{`{"opaque":1}`, `{"opaque":2}`} {
		wg.Add(1)
		go func(data string) {
			defer wg.Done()
			_, err := store.Save(json.RawMessage(data), before.Revision)
			results <- err
		}(data)
	}
	wg.Wait()
	close(results)
	success, conflicts := 0, 0
	for err := range results {
		if err == nil {
			success++
		} else if errors.Is(err, ErrConflict) {
			conflicts++
		} else {
			t.Fatal(err)
		}
	}
	if success != 1 || conflicts != 1 {
		t.Fatalf("success=%d conflicts=%d", success, conflicts)
	}
}

func TestCorruptOverrideIsNotSilentlyReplaced(t *testing.T) {
	for _, data := range []string{"{", "null", strings.Repeat(" ", 16385)} {
		_, store := fixture(t)
		if err := os.WriteFile(store.override, []byte(data), 0600); err != nil {
			t.Fatal(err)
		}
		_, err := store.Load()
		code, found := fault.CodeOf(err)
		if !found || (code != fault.StorageCorrupt && code != fault.LimitExceeded) {
			t.Fatal("corrupt override did not fail", err)
		}
		if _, err := store.Save(json.RawMessage(`{"new":true}`), ""); err == nil {
			t.Fatal("corrupt override was overwritten")
		}
		actual, _ := os.ReadFile(store.override)
		if string(actual) != data {
			t.Fatal("corrupt override bytes changed")
		}
	}
}

func TestMissingDependenciesAndByteBoundRevision(t *testing.T) {
	_, store := fixture(t)
	before, _ := store.Load()
	changed := append(bytes.Clone(before.Document), '\n')
	if err := os.WriteFile(store.defaults, changed, 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := store.Save(before.Document, before.Revision); !errors.Is(err, ErrConflict) {
		t.Fatal("external file change did not invalidate revision", err)
	}
	if err := os.Remove(store.defaults); err != nil {
		t.Fatal(err)
	}
	_, err := store.Load()
	if code, _ := fault.CodeOf(err); code != fault.StorageMissing {
		t.Fatal("missing dependency misclassified", err)
	}
}

func TestPublishFailureLeavesDefaultsReadable(t *testing.T) {
	defaults, original := fixture(t)
	store := New(original.defaults, filepath.Join(filepath.Dir(original.defaults), "missing", "local.json"), original.maxBytes)
	before, err := store.Load()
	if err != nil {
		t.Fatal(err)
	}
	_, err = store.Save(json.RawMessage(`{"new":true}`), before.Revision)
	if code, _ := fault.CodeOf(err); code != fault.StorageIO {
		t.Fatal("publish failure misclassified", err)
	}
	after, err := store.Load()
	if err != nil || after.Revision != before.Revision || !bytes.Equal(after.Document, defaults) {
		t.Fatal("failed publish changed stored settings", err)
	}
}
