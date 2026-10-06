package content

import (
	"bytes"
	"encoding/binary"
	"os"
	"path/filepath"
	"testing"
)

func TestCatalogRejectsMalformedRecords(t *testing.T) {
	store, err := OpenWithOptions(t.TempDir(), MaxChunk, Options{
		InlineBytes: MaxChunk, CatalogMiB: 1, MaxObjects: 100,
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err = store.PutText("one object"); err != nil {
		t.Fatal(err)
	}
	if err = store.Flush(); err != nil {
		t.Fatal(err)
	}
	valid, err := os.ReadFile(filepath.Join(store.root, "catalog.pfca"))
	if err != nil {
		t.Fatal(err)
	}
	cases := map[string][]byte{
		"header":    valid[:4],
		"truncated": valid[:len(valid)-1],
		"trailing":  append(bytes.Clone(valid), 0),
		"duplicate": append(bytes.Clone(valid), valid[9:]...),
		"count":     bytes.Clone(valid),
		"length":    bytes.Clone(valid),
	}
	binary.BigEndian.PutUint32(cases["duplicate"][5:9], 2)
	binary.BigEndian.PutUint32(cases["count"][5:9], 101)
	binary.BigEndian.PutUint32(cases["length"][41:45], MaxChunk+7)
	for name, data := range cases {
		t.Run(name, func(t *testing.T) {
			root := t.TempDir()
			if err := os.WriteFile(filepath.Join(root, "catalog.pfca"), data, 0600); err != nil {
				t.Fatal(err)
			}
			if _, err := OpenWithOptions(root, MaxChunk, Options{
				CatalogMiB: 1, MaxObjects: 100,
			}); err == nil {
				t.Fatal("malformed catalog accepted")
			}
		})
	}
}

func TestCatalogCapacityFallsBackWithoutLosingExistingObjects(t *testing.T) {
	root := t.TempDir()
	options := Options{InlineBytes: MaxChunk, CatalogMiB: 1, MaxObjects: 100}
	store, err := OpenWithOptions(root, MaxChunk, options)
	if err != nil {
		t.Fatal(err)
	}
	refs := make([]Ref, 0, 18)
	for i := range 18 {
		data := bytes.Repeat([]byte{byte(i)}, MaxChunk)
		ref, err := store.PutNotes(data)
		if err != nil {
			t.Fatal(err)
		}
		refs = append(refs, ref)
	}
	if err = store.Flush(); err != nil {
		t.Fatal(err)
	}
	if len(store.inline) >= len(refs) {
		t.Fatal("fixture did not reach catalog capacity")
	}
	info, err := os.Stat(filepath.Join(root, "catalog.pfca"))
	if err != nil || info.Size() > 1024*1024 {
		t.Fatal("catalog exceeded configured capacity", err)
	}
	// Disabling future inline writes must still read the already published catalog.
	options.InlineBytes = 0
	reopened, err := OpenWithOptions(root, MaxChunk, options)
	if err != nil {
		t.Fatal(err)
	}
	session := reopened.Session(4*1024*1024, 100)
	for i, ref := range refs {
		data, err := session.Notes(ref, MaxChunk)
		if err != nil || len(data) != MaxChunk || data[0] != byte(i) {
			t.Fatal("inline/loose fallback lost an object", i, err)
		}
	}
	if err = reopened.VerifyFiles(session.Files(), 4*1024*1024, 100); err != nil {
		t.Fatal("warm fallback verification", err)
	}
}
