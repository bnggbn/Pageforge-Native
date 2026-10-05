package api

import (
	"github.com/bnggbn/Pageforge-Native/backend/internal/library"
	"net/http"
)

func (s *Server) loadEvidence(w http.ResponseWriter, r *http.Request) {
	wall, err := s.Store.LoadEvidence(r.PathValue("id"))
	respond(w, wall, err)
}
func (s *Server) saveEvidence(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, int64(s.Config.EvidenceWall.LayoutMiB)*1024*1024)
	var input library.SaveEvidence
	if err := s.body(w, r, &input); err != nil {
		respond(w, nil, err)
		return
	}
	wall, err := s.Store.SaveEvidence(r.PathValue("id"), input)
	respond(w, wall, err)
}
