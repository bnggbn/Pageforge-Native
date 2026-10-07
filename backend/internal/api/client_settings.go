package api

import (
	"encoding/json"
	"net/http"

	"github.com/bnggbn/Pageforge-Native/backend/internal/fault"
)

// The legacy /v1/design URL persists a client-owned document without interpreting it.
func (s *Server) loadClientSettings(w http.ResponseWriter, r *http.Request) {
	if s.ClientSettings == nil {
		respond(w, nil, fault.New(fault.Internal, "client settings storage is not configured"))
		return
	}
	value, err := s.ClientSettings.Load()
	respond(w, value, err)
}

func (s *Server) saveClientSettings(w http.ResponseWriter, r *http.Request) {
	if s.ClientSettings == nil {
		respond(w, nil, fault.New(fault.Internal, "client settings storage is not configured"))
		return
	}
	// Allow the small transport wrapper in addition to the bounded document.
	r.Body = http.MaxBytesReader(w, r.Body, s.ClientSettings.MaxBytes()+1024)
	var input struct {
		Document         json.RawMessage `json:"document"`
		ExpectedRevision string          `json:"expectedRevision"`
	}
	if err := s.body(w, r, &input); err != nil {
		respond(w, nil, err)
		return
	}
	value, err := s.ClientSettings.Save(input.Document, input.ExpectedRevision)
	respond(w, value, err)
}
