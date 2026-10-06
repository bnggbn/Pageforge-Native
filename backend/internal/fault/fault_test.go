package fault

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"testing"
)

func TestCodesSurviveWrappingWithoutLosingCauses(t *testing.T) {
	_, encodeErr := json.Marshal(make(chan string))
	cause := &fs.PathError{Op: "open", Path: "private/library/object", Err: fs.ErrNotExist}
	err := fmt.Errorf("load version: %w", Read(cause))
	if code, found := CodeOf(err); !found || code != StorageMissing {
		t.Fatal("dependency code lost", code)
	}
	if !errors.Is(err, fs.ErrNotExist) {
		t.Fatal("missing-file cause lost; create/optional-file semantics would break")
	}
	var path *fs.PathError
	if !errors.As(err, &path) || path != cause {
		t.Fatal("original diagnostic cause lost")
	}
	if Ensure(StorageIO, "outer fallback", err) != err {
		t.Fatal("boundary replaced an existing code")
	}
	if _, found := CodeOf(errors.New("STORAGE_MISSING")); found {
		t.Fatal("messages used as error codes")
	}
	for _, test := range []struct {
		err  error
		code Code
	}{
		{Read(io.ErrUnexpectedEOF), StorageCorrupt},
		{Read(fs.ErrPermission), StorageIO},
		{Write(fs.ErrNotExist), StorageIO},
		{Encode(encodeErr), Internal},
		{Wrap(NotFound, "missing resource", err), NotFound},
	} {
		if code, _ := CodeOf(test.err); code != test.code {
			t.Fatal("incorrect source classification", code, test.code)
		}
	}
	if Read(nil) != nil || Write(nil) != nil || Wrap(Internal, "unused", nil) != nil {
		t.Fatal("successful operations turned into errors")
	}
}
