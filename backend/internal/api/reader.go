package api

import (
	"fmt"
	"github.com/bnggbn/Pageforge-Native/backend/internal/model"
	"net/http"
)

type revisionSummary struct {
	ID        string `json:"id"`
	Kind      string `json:"kind"`
	CreatedAt string `json:"createdAt"`
}

func readerProjection(b model.Book, r *http.Request) any {
	if r.URL.Query().Get("view") != "reader" || len(b.Revisions) == 0 {
		return b
	}
	history := make([]revisionSummary, 0, len(b.Revisions))
	for _, revision := range b.Revisions {
		history = append(history, revisionSummary{revision.ID, revision.Kind, revision.CreatedAt})
	}
	count := len(b.Revisions)
	b.Revisions = b.Revisions[count-1:]
	return struct {
		model.Book
		History       []revisionSummary `json:"history"`
		RevisionCount int               `json:"revisionCount"`
	}{b, history, count}
}
func (s *Server) revision(w http.ResponseWriter, r *http.Request) {
	book, err := s.Store.Load(r.PathValue("id"))
	if err != nil {
		respond(w, nil, err)
		return
	}
	for _, revision := range book.Revisions {
		if revision.ID == r.PathValue("revision") {
			respond(w, revision, nil)
			return
		}
	}
	respond(w, nil, fmt.Errorf("版本不在此主線"))
}
