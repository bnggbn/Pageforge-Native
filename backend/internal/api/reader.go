package api

import (
	"github.com/bnggbn/Pageforge-Native/backend/internal/library"
	"github.com/bnggbn/Pageforge-Native/backend/internal/model"
	"net/http"
)

type revisionSummary = model.RevisionSummary

func readerProjection(b model.Book, r *http.Request) any {
	if r.URL.Query().Get("view") != "reader" || len(b.Revisions) == 0 {
		return b
	}
	history, count := b.History, b.RevisionCount
	if count == 0 {
		count = len(b.Revisions)
		history = make([]model.RevisionSummary, 0, count)
		for _, revision := range b.Revisions {
			history = append(history, model.RevisionSummary{ID: revision.ID, Kind: revision.Kind, CreatedAt: revision.CreatedAt})
		}
	}
	b.Revisions = b.Revisions[len(b.Revisions)-1:]
	return struct {
		model.Book
		History       []model.RevisionSummary `json:"history"`
		RevisionCount int                     `json:"revisionCount"`
	}{b, history, count}
}
func (s *Server) loadBook(r *http.Request) (model.Book, error) {
	if r.URL.Query().Get("view") == "reader" {
		return s.Store.LoadReader(r.PathValue("id"))
	}
	return s.Store.LoadHistory(r.PathValue("id"))
}
func (s *Server) commitBook(r *http.Request, input library.Commit) (model.Book, error) {
	if r.URL.Query().Get("view") == "reader" {
		return s.Store.CommitReader(r.PathValue("id"), input)
	}
	return s.Store.CommitHistory(r.PathValue("id"), input)
}
func (s *Server) revision(w http.ResponseWriter, r *http.Request) {
	revision, err := s.Store.LoadRevision(r.PathValue("id"), r.PathValue("revision"))
	respond(w, revision, err)
}
