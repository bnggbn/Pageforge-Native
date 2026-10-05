package design

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

func fixture(t *testing.T) ([]byte, *Store) {
	t.Helper()
	data, err := os.ReadFile(filepath.Join("..", "..", "..", "pageforge.design.json"))
	if err != nil {
		t.Fatal(err)
	}
	root := t.TempDir()
	if err = os.WriteFile(filepath.Join(root, "pageforge.design.json"), data, 0600); err != nil {
		t.Fatal(err)
	}
	return data, New(root)
}
func TestRejectInvalidDesign(t *testing.T) {
	data, _ := fixture(t)
	var valid map[string]any
	json.Unmarshal(data, &valid)
	cases := []func(map[string]any){
		func(d map[string]any) { d["schemaVersion"] = 2 },
		func(d map[string]any) { d["script"] = "execute()" },
		func(d map[string]any) { d["theme"].(map[string]any)["paper"] = "url(file:///secret)" },
		func(d map[string]any) { d["theme"].(map[string]any)["headingFont"] = "unknown" },
		func(d map[string]any) { delete(d["library"].(map[string]any), "showInvitation") },
		func(d map[string]any) { d["library"].(map[string]any)["showInvitation"] = nil },
		func(d map[string]any) { d["library"].(map[string]any)["gap"] = 5000 },
		func(d map[string]any) { d["reader"].(map[string]any)["lineHeight"] = 0 },
	}
	for i, mutate := range cases {
		var changed map[string]any
		json.Unmarshal(data, &changed)
		mutate(changed)
		encoded, _ := json.Marshal(changed)
		if _, err := Decode(encoded); err == nil {
			t.Fatalf("case %d accepted", i)
		}
	}
	if _, err := Decode([]byte(strings.Repeat(" ", MaxBytes+1))); err == nil {
		t.Fatal("oversized JSON accepted")
	}
	if _, err := Decode(append(data, []byte("{}")...)); err == nil {
		t.Fatal("trailing JSON accepted")
	}
}
func TestSaveReopenAndConflict(t *testing.T) {
	data, store := fixture(t)
	before, err := store.Load()
	if err != nil {
		t.Fatal(err)
	}
	next := before.Document
	next.Theme.Accent = "#335577"
	saved, err := store.Save(next, before.Revision)
	if err != nil {
		t.Fatal(err)
	}
	reopened, err := New(store.root).Load()
	if err != nil || reopened != saved {
		t.Fatal("saved design not restored", err)
	}
	if _, err = store.Save(before.Document, before.Revision); !errors.Is(err, ErrConflict) {
		t.Fatal("stale write accepted", err)
	}
	next.Reader.LineHeight = 900
	if _, err = store.Save(next, saved.Revision); err == nil {
		t.Fatal("invalid write accepted")
	}
	final, _ := store.Load()
	if final != saved {
		t.Fatal("failed write changed saved design")
	}
	defaults, _ := os.ReadFile(filepath.Join(store.root, "pageforge.design.json"))
	if string(defaults) != string(data) {
		t.Fatal("defaults overwritten")
	}
}
func TestConcurrentSaveKeepsOneWinner(t *testing.T) {
	_, store := fixture(t)
	before, _ := store.Load()
	var wg sync.WaitGroup
	results := make(chan error, 2)
	for _, color := range []string{"#123456", "#654321"} {
		wg.Add(1)
		go func(color string) {
			defer wg.Done()
			next := before.Document
			next.Theme.Ink = color
			_, err := store.Save(next, before.Revision)
			results <- err
		}(color)
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
