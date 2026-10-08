package api

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/bnggbn/Pageforge-Native/backend/internal/fault"
	"github.com/bnggbn/vax-action-history/storage"
)

func TestStorageSDKFailuresKeepPublicContractAndHideDiagnostics(t *testing.T) {
	for _, test := range []struct {
		kind   storage.Kind
		code   fault.Code
		status int
	}{
		{storage.Missing, fault.StorageMissing, 500}, {storage.Corrupt, fault.StorageCorrupt, 500},
		{storage.IO, fault.StorageIO, 500}, {storage.LimitExceeded, fault.LimitExceeded, 413},
		{storage.UnsupportedFormat, fault.UnsupportedStorage, 500}, {storage.UnsafePath, fault.UnsafePath, 400},
		{storage.InvalidOptions, fault.Internal, 500}, {storage.Kind("future-kind"), fault.Internal, 500},
	} {
		recorder := httptest.NewRecorder()
		err := fmt.Errorf("SDK boundary: %w", &storage.Error{Kind: test.kind, Message: "private/library/secret.pfo"})
		respond(recorder, nil, err)
		var body errorResponse
		if err = json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
			t.Fatal(err)
		}
		if recorder.Code != test.status || body.Code != test.code || strings.Contains(body.Error, "private/") {
			t.Fatal("SDK failure changed public contract", body.Code, recorder.Code)
		}
	}
	recorder := httptest.NewRecorder()
	respond(recorder, nil, &storage.Error{Kind: storage.InvalidInput, Message: "text must be UTF-8"})
	if recorder.Code != http.StatusBadRequest {
		t.Fatal("SDK input failure lost validation status")
	}
}
