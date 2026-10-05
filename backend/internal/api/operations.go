package api

import (
	"encoding/base64"
	"fmt"
	"net/http"

	"github.com/bnggbn/Pageforge-Native/backend/internal/compare"
	"github.com/bnggbn/Pageforge-Native/backend/internal/library"
	"github.com/bnggbn/Pageforge-Native/backend/internal/model"
)

func (s *Server) importBook(w http.ResponseWriter, r *http.Request) {
	var input struct {
		Filename string `json:"filename"`
		Source   string `json:"source"`
	}
	if err := s.body(w, r, &input); err != nil {
		respond(w, nil, err)
		return
	}
	bytes, err := base64.StdEncoding.DecodeString(input.Source)
	if err != nil {
		respond(w, nil, err)
		return
	}
	id, duplicate, err := s.Store.Import(input.Filename, bytes)
	respond(w, map[string]any{"id": id, "duplicate": duplicate}, err)
}
func (s *Server) commit(w http.ResponseWriter, r *http.Request) {
	var input library.Commit
	if err := s.body(w, r, &input); err != nil {
		respond(w, nil, err)
		return
	}
	book, err := s.Store.Commit(r.PathValue("id"), input)
	respond(w, book, err)
}
func (s *Server) progress(w http.ResponseWriter, r *http.Request) {
	var input model.Position
	if err := s.body(w, r, &input); err != nil {
		respond(w, nil, err)
		return
	}
	err := s.Store.SaveProgress(r.PathValue("id"), input)
	respond(w, map[string]bool{"saved": err == nil}, err)
}
func (s *Server) draft(w http.ResponseWriter, r *http.Request) {
	var input struct {
		Copy            model.Draft `json:"copy"`
		ExpectedVersion *string     `json:"expectedVersion"`
	}
	if err := s.body(w, r, &input); err != nil {
		respond(w, nil, err)
		return
	}
	copy, err := s.Store.SaveDraft(r.PathValue("id"), input.Copy, input.ExpectedVersion)
	respond(w, copy, err)
}
func (s *Server) diff(w http.ResponseWriter, r *http.Request) {
	var input struct {
		From string `json:"from"`
		To   string `json:"to"`
	}
	if err := s.body(w, r, &input); err != nil {
		respond(w, nil, err)
		return
	}
	book, err := s.Store.Load(r.PathValue("id"))
	if err != nil {
		respond(w, nil, err)
		return
	}
	var before, after *model.Revision
	for i := range book.Revisions {
		revision := &book.Revisions[i]
		if revision.ID == input.From {
			before = revision
		}
		if revision.ID == input.To {
			after = revision
		}
	}
	if before == nil || after == nil {
		respond(w, nil, fmt.Errorf("比較來源不存在"))
		return
	}
	parts, err := compare.Text(before.Content, after.Content, s.Config.Diff.MaxCharacters, s.Config.Diff.TimeoutMs)
	respond(w, parts, err)
}
