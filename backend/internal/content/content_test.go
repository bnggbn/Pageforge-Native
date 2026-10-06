package content

import (
	"bytes"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"math/rand"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func fixtureText(count int) string {
	random := rand.New(rand.NewSource(526))
	alphabet := []rune("abcdefghijklmnop0123456789文字章節🌿🧩\n ")
	var out strings.Builder
	for range count {
		out.WriteRune(alphabet[random.Intn(len(alphabet))])
	}
	return out.String()
}
func fixtureStore(t *testing.T) *Store {
	t.Helper()
	store, err := Open(t.TempDir(), 5*1024*1024)
	if err != nil {
		t.Fatal(err)
	}
	return store
}
func diskBytes(t *testing.T, root string) int64 {
	t.Helper()
	var size int64
	err := filepath.WalkDir(root, func(file string, entry os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if !entry.IsDir() {
			info, err := entry.Info()
			if err != nil {
				return err
			}
			size += info.Size()
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	return size
}

func TestTextObjectsRoundTripAndResynchronize(t *testing.T) {
	store := fixtureStore(t)
	text := fixtureText(700000)
	root, err := store.PutText(text)
	if err != nil {
		t.Fatal(err)
	}
	before := diskBytes(t, store.root)
	repeated, err := store.PutText(text)
	if err != nil || root != repeated || diskBytes(t, store.root) != before {
		t.Fatal("repeated text was not reused", err)
	}
	changed, err := store.PutText("新增🌿\n" + text)
	if err != nil {
		t.Fatal(err)
	}
	added := diskBytes(t, store.root) - before
	if added >= before/4 {
		t.Fatalf("prefix insert rewrote too much: added %d of %d", added, before)
	}
	session := store.Session(10*1024*1024, 10000)
	restored, err := session.Text(changed, 5*1024*1024)
	if err != nil || restored != "新增🌿\n"+text {
		t.Fatal("changed round trip failed", err)
	}
	old, err := session.Text(root, 5*1024*1024)
	if err != nil || old != text {
		t.Fatal("old text changed", err)
	}
	if _, err = session.Text(root, root.Bytes-1); err == nil {
		t.Fatal("expanded text capacity ignored")
	}
}

func TestEmptyUnicodeAndTypedObjects(t *testing.T) {
	store := fixtureStore(t)
	for _, text := range []string{"", "a\r\n\n中文e\u0301👩‍💻\n", strings.Repeat("中🌿", 20000)} {
		ref, err := store.PutText(text)
		if err != nil {
			t.Fatal(err)
		}
		result, err := store.Session(5*1024*1024, 10000).Text(ref, 5*1024*1024)
		if err != nil || result != text {
			t.Fatal("Unicode round trip", err)
		}
	}
	if _, err := store.PutText(string([]byte{0xff})); err == nil {
		t.Fatal("invalid UTF-8 accepted")
	}
	notes, err := store.PutNotes([]byte(`[]`))
	if err != nil {
		t.Fatal(err)
	}
	if err = store.Session(1024, 10).VerifyText(notes, 1024); err == nil {
		t.Fatal("notes used as text")
	}
	text, _ := store.PutText("[]")
	if text.Hash == notes.Hash {
		t.Fatal("object kinds are not separated")
	}
	if _, err = store.Session(1024, 10).Notes(text, 1024); err == nil {
		t.Fatal("text used as notes")
	}
}

func TestActualBytesMissingObjectsAndBudgets(t *testing.T) {
	store := fixtureStore(t)
	ref, _ := store.PutText("original text")
	file, _ := store.location(ref.Hash)
	info, _ := os.Stat(file)
	data, _ := os.ReadFile(file)
	data[len(data)-1] ^= 1
	if err := os.WriteFile(file, data, 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Chtimes(file, info.ModTime(), info.ModTime()); err != nil {
		t.Fatal(err)
	}
	if _, err := store.Session(1024, 10).Text(ref, 1024); err == nil {
		t.Fatal("tampering accepted")
	}
	if _, err := store.PutText("original text"); err == nil {
		t.Fatal("corrupt object overwritten")
	}
	if err := os.Remove(file); err != nil {
		t.Fatal(err)
	}
	if _, err := store.Session(1024, 10).Text(ref, 1024); err == nil {
		t.Fatal("missing object accepted")
	}
	ref, _ = store.PutText(fixtureText(50000))
	if _, err := store.Session(10, 100).Text(ref, 5*1024*1024); err == nil {
		t.Fatal("physical bytes ignored")
	}
	if _, err := store.Session(5*1024*1024, 1).Text(ref, 5*1024*1024); err == nil {
		t.Fatal("object count ignored")
	}
	if _, err := store.Session(1024, 10).Text(Ref{Hash: "../escape", Bytes: 0}, 1024); err == nil {
		t.Fatal("unsafe hash accepted")
	}
}

func TestBranchOrderSizesAndInvalidLeaves(t *testing.T) {
	store := fixtureStore(t)
	a, _ := store.PutText("A")
	b, _ := store.PutText("中文字")
	branch := func(children []Ref, size int64) Ref {
		payload := make([]byte, 1+40*len(children))
		payload[0] = byte(len(children))
		for i, child := range children {
			hash, _ := hex.DecodeString(child.Hash)
			copy(payload[1+40*i:], hash)
			binary.BigEndian.PutUint64(payload[33+40*i:], uint64(child.Bytes))
		}
		ref, err := store.put(branchKind, payload, size)
		if err != nil {
			t.Fatal(err)
		}
		return ref
	}
	forward := branch([]Ref{a, b}, a.Bytes+b.Bytes)
	reverse := branch([]Ref{b, a}, a.Bytes+b.Bytes)
	first, err := store.Session(1024, 10).Text(forward, 1024)
	if err != nil || first != "A中文字" {
		t.Fatal("forward order", err)
	}
	second, err := store.Session(1024, 10).Text(reverse, 1024)
	if err != nil || second != "中文字A" || forward.Hash == reverse.Hash {
		t.Fatal("order not committed", err)
	}
	bad := b
	bad.Bytes++
	if _, err = store.Session(1024, 10).Text(branch([]Ref{a, bad}, a.Bytes+bad.Bytes), 1024); err == nil {
		t.Fatal("incorrect child length accepted")
	}
	invalid, _ := store.put(textKind, []byte{0xff}, 1)
	if _, err = store.Session(1024, 10).Text(invalid, 1024); err == nil {
		t.Fatal("invalid leaf accepted")
	}
	huge, _ := store.put(textKind, bytes.Repeat([]byte("a"), MaxChunk+1), MaxChunk+1)
	if _, err = store.Session(1024*1024, 10).Text(huge, 1024*1024); err == nil {
		t.Fatal("oversized leaf accepted")
	}
}

func TestObjectFormatGoldenVectors(t *testing.T) {
	data, err := os.ReadFile("testdata/objects-v1.json")
	if err != nil {
		t.Fatal(err)
	}
	var vectors []struct {
		Name         string
		Kind         byte
		Hash         string
		ObjectHex    string
		LogicalBytes int64
		Text         string
	}
	if err = json.Unmarshal(data, &vectors); err != nil {
		t.Fatal(err)
	}
	store := fixtureStore(t)
	for _, vector := range vectors {
		wire, err := hex.DecodeString(vector.ObjectHex)
		if err != nil {
			t.Fatal(err)
		}
		ref, err := store.put(vector.Kind, wire[len(magic)+1:], vector.LogicalBytes)
		if err != nil || ref.Hash != vector.Hash {
			t.Fatal("golden encoding", vector.Name, err)
		}
		if vector.Kind == notesKind {
			payload, err := store.Session(1024, 10).Notes(ref, 1024)
			if err != nil || string(payload) != "[]" {
				t.Fatal("golden notes", err)
			}
		} else {
			text, err := store.Session(1024, 10).Text(ref, 1024)
			if err != nil || text != vector.Text {
				t.Fatal("golden text", vector.Name, err)
			}
		}
	}
}

func TestObjectDepthLimit(t *testing.T) {
	store := fixtureStore(t)
	leaf, err := store.PutText("a")
	if err != nil {
		t.Fatal(err)
	}
	root := leaf
	for range maxDepth + 1 {
		payload := make([]byte, 81)
		payload[0] = 2
		for i, child := range []Ref{root, leaf} {
			hash, _ := hex.DecodeString(child.Hash)
			copy(payload[1+40*i:], hash)
			binary.BigEndian.PutUint64(payload[33+40*i:], uint64(child.Bytes))
		}
		root, err = store.put(branchKind, payload, root.Bytes+leaf.Bytes)
		if err != nil {
			t.Fatal(err)
		}
	}
	if _, err = store.Session(1024*1024, 1000).Text(root, 1024*1024); err == nil {
		t.Fatal("excessive depth accepted")
	}
}

func TestCatalogPublicationAndSmallObjectReuse(t *testing.T) {
	root := t.TempDir()
	store, err := OpenWithOptions(root, 1024*1024, Options{InlineBytes: 4096, CatalogMiB: 1, MaxObjects: 100})
	if err != nil {
		t.Fatal(err)
	}
	text, err := store.PutText("中文🌿")
	if err != nil {
		t.Fatal(err)
	}
	notes, err := store.PutNotes([]byte("[]"))
	if err != nil {
		t.Fatal(err)
	}
	if err = store.Flush(); err != nil {
		t.Fatal(err)
	}
	before := diskBytes(t, root)
	if _, err = store.PutText("中文🌿"); err != nil {
		t.Fatal(err)
	}
	if err = store.Flush(); err != nil {
		t.Fatal(err)
	}
	if diskBytes(t, root) != before {
		t.Fatal("catalog reused object grew disk")
	}
	reopened, err := Open(root, 1024*1024)
	if err != nil {
		t.Fatal(err)
	}
	session := reopened.Session(1024*1024, 100)
	actual, err := session.Text(text, 1024*1024)
	if err != nil || actual != "中文🌿" {
		t.Fatal("catalog text roundtrip", err)
	}
	if _, err = session.Notes(notes, 1024*1024); err != nil {
		t.Fatal(err)
	}
	if err = reopened.VerifyFiles(session.Files(), 1024*1024, 100); err != nil {
		t.Fatal("warm closure", err)
	}
	file := filepath.Join(root, "catalog.pfca")
	data, err := os.ReadFile(file)
	if err != nil {
		t.Fatal(err)
	}
	data[len(data)-1] ^= 1
	if err = os.WriteFile(file, data, 0600); err != nil {
		t.Fatal(err)
	}
	if _, err = Open(root, 1024*1024); err == nil {
		t.Fatal("catalog hash substitution accepted")
	}
}
