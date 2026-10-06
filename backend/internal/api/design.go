package api

import (
	"encoding/json"
	"net/http"

	"github.com/bnggbn/Pageforge-Native/backend/internal/design"
	"github.com/bnggbn/Pageforge-Native/backend/internal/fault"
)

func (s *Server) loadDesign(w http.ResponseWriter, r *http.Request) {
	if s.Design == nil {
		respond(w, nil, fault.New(fault.Internal, "外觀服務未設定"))
		return
	}
	value, err := s.Design.Load()
	respond(w, value, err)
}
func (s *Server) saveDesign(w http.ResponseWriter, r *http.Request) {
	if s.Design == nil {
		respond(w, nil, fault.New(fault.Internal, "外觀服務未設定"))
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, design.MaxBytes)
	var input struct {
		Document         json.RawMessage `json:"document"`
		ExpectedRevision string          `json:"expectedRevision"`
	}
	if err := s.body(w, r, &input); err != nil {
		respond(w, nil, err)
		return
	}
	document, err := design.Decode(input.Document)
	if err != nil {
		respond(w, nil, err)
		return
	}
	value, err := s.Design.Save(document, input.ExpectedRevision)
	respond(w, value, err)
}
