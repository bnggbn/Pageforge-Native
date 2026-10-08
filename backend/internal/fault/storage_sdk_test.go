package fault

import (
	"errors"
	"fmt"
	"io/fs"
	"testing"

	"github.com/bnggbn/vax-action-history/storage"
)

func TestStorageSDKKindsMapToExistingAPICodes(t *testing.T) {
	for _, test := range []struct {
		kind storage.Kind
		code Code
	}{
		{storage.InvalidInput, InvalidRequest}, {storage.InvalidOptions, Internal},
		{storage.LimitExceeded, LimitExceeded}, {storage.Corrupt, StorageCorrupt},
		{storage.Missing, StorageMissing}, {storage.IO, StorageIO},
		{storage.UnsupportedFormat, UnsupportedStorage}, {storage.UnsafePath, UnsafePath},
		{storage.Kind("future-kind"), Internal},
	} {
		source := &storage.Error{Kind: test.kind, Message: "SDK diagnostic"}
		wrapped := fmt.Errorf("load version: %w", source)
		if code, found := CodeOf(wrapped); !found || code != test.code {
			t.Fatal("incorrect SDK mapping", test.kind, code)
		}
		if Read(wrapped) != wrapped || Write(wrapped) != wrapped {
			t.Fatal("SDK classification replaced")
		}
		if code, _ := CodeOf(Wrap(Conflict, "application decision", source)); code != Conflict {
			t.Fatal("outer application classification lost")
		}
	}
	objects, err := storage.Open(t.TempDir(), storage.MaxChunk)
	if err != nil {
		t.Fatal(err)
	}
	_, err = objects.Session(1024, 10).Blob(storage.Ref{Hash: fmt.Sprintf("%064x", 1), Bytes: 1}, 1024)
	if code, _ := CodeOf(err); code != StorageMissing || !errors.Is(err, fs.ErrNotExist) {
		t.Fatal("missing SDK dependency classification or cause lost", err)
	}
	var pathError *fs.PathError
	if !errors.As(err, &pathError) {
		t.Fatal("SDK path cause was lost")
	}
}
