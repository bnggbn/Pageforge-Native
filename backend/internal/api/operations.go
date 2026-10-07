package api

import (
	"encoding/base64"
	"net/http"

	"github.com/bnggbn/Pageforge-Native/backend/internal/compare"
	"github.com/bnggbn/Pageforge-Native/backend/internal/fault"
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
		respond(w, nil, fault.Wrap(fault.InvalidRequest, "文件來源編碼無效", err))
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
	book, err := s.commitBook(r, input)
	respond(w, readerProjection(book, r), err)
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
	before, err := s.Store.LoadRevision(r.PathValue("id"), input.From)
	if err != nil {
		respond(w, nil, err)
		return
	}
	after, err := s.Store.LoadRevision(r.PathValue("id"), input.To)
	if err != nil {
		respond(w, nil, err)
		return
	}
	parts, err := compare.Text(before.Content, after.Content, s.Config.Diff.MaxCharacters, s.Config.Diff.TimeoutMs)
	respond(w, parts, err)
}
