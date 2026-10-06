package content

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/bnggbn/Pageforge-Native/backend/internal/fault"
)

func TestObjectFailureCodesDistinguishCapacityCorruptionAndAbsence(t *testing.T) {
	store := fixtureStore(t)
	ref, err := store.PutText("原文🌿")
	if err != nil {
		t.Fatal(err)
	}
	assertCode := func(err error, expected fault.Code) {
		t.Helper()
		if code, found := fault.CodeOf(err); !found || code != expected {
			t.Fatal("wrong object failure code", code, expected, err)
		}
	}
	_, err = store.Session(1, 10).Text(ref, 1024)
	assertCode(err, fault.LimitExceeded)
	file, err := store.location(ref.Hash)
	if err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(file)
	if err != nil {
		t.Fatal(err)
	}
	data[len(data)-1] ^= 1
	if err = os.WriteFile(file, data, 0600); err != nil {
		t.Fatal(err)
	}
	_, err = store.Session(1024, 10).Text(ref, 1024)
	assertCode(err, fault.StorageCorrupt)
	if err = os.Remove(file); err != nil {
		t.Fatal(err)
	}
	_, err = store.Session(1024, 10).Text(ref, 1024)
	assertCode(err, fault.StorageMissing)
	if !errors.Is(err, os.ErrNotExist) {
		t.Fatal("missing dependency no longer unwraps")
	}
	ref, err = store.put(9, []byte("future"), 6)
	if err != nil {
		t.Fatal(err)
	}
	_, err = store.Session(1024, 10).Text(ref, 1024)
	assertCode(err, fault.UnsupportedStorage)
}

func TestFutureWireVersionIsUnsupportedRatherThanCorrupt(t *testing.T) {
	store := fixtureStore(t)
	wire := []byte{'P', 'F', 'C', 'O', 2, 0, 'a'}
	sum := sha256.Sum256(wire)
	ref := Ref{Hash: hex.EncodeToString(sum[:]), Bytes: 1}
	file, err := store.location(ref.Hash)
	if err != nil {
		t.Fatal(err)
	}
	if err = os.MkdirAll(filepath.Dir(file), 0700); err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(file, wire, 0600); err != nil {
		t.Fatal(err)
	}
	_, err = store.Session(1024, 10).Text(ref, 1024)
	if code, _ := fault.CodeOf(err); code != fault.UnsupportedStorage {
		t.Fatal("valid future wire hash misclassified", code, err)
	}
}
