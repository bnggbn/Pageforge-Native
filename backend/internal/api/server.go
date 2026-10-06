package api

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"

	"github.com/bnggbn/Pageforge-Native/backend/internal/config"
	"github.com/bnggbn/Pageforge-Native/backend/internal/design"
	"github.com/bnggbn/Pageforge-Native/backend/internal/library"
)

type Server struct {
	Design   *design.Store
	Store    *library.Store
	Config   config.Config
	Token    string
	Shutdown func()
}

func New(store *library.Store, c config.Config, shutdown func()) *Server {
	token := make([]byte, 32)
	if _, err := rand.Read(token); err != nil {
		panic(err)
	}
	return &Server{Store: store, Config: c, Token: hex.EncodeToString(token), Shutdown: shutdown}
}
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /v1/design", s.loadDesign)
	mux.HandleFunc("PUT /v1/design", s.saveDesign)
	mux.HandleFunc("GET /v1/status", func(w http.ResponseWriter, r *http.Request) {
		send(w, map[string]any{"name": "Pageforge", "config": s.Config})
	})
	mux.HandleFunc("GET /v1/books", func(w http.ResponseWriter, r *http.Request) { books, err := s.Store.List(); respond(w, books, err) })
	mux.HandleFunc("GET /v1/books/{id}", func(w http.ResponseWriter, r *http.Request) {
		book, err := s.Store.Load(r.PathValue("id"))
		respond(w, readerProjection(book, r), err)
	})
	mux.HandleFunc("GET /v1/books/{id}/versions/{revision}", s.revision)
	mux.HandleFunc("POST /v1/import", s.importBook)
	mux.HandleFunc("POST /v1/collection/sync", func(w http.ResponseWriter, r *http.Request) {
		count, err := s.Store.SyncCollection()
		respond(w, map[string]int{"imported": count}, err)
	})
	mux.HandleFunc("POST /v1/books/{id}/versions", s.commit)
	mux.HandleFunc("PUT /v1/books/{id}/progress", s.progress)
	mux.HandleFunc("GET /v1/books/{id}/drafts", func(w http.ResponseWriter, r *http.Request) {
		copies, err := s.Store.Drafts(r.PathValue("id"))
		respond(w, copies, err)
	})
	mux.HandleFunc("PUT /v1/books/{id}/drafts", s.draft)
	mux.HandleFunc("DELETE /v1/books/{id}/drafts/{draft}", func(w http.ResponseWriter, r *http.Request) {
		err := s.Store.RemoveDraft(r.PathValue("id"), r.PathValue("draft"), r.Header.Get("X-Draft-Version"))
		respond(w, map[string]bool{"saved": err == nil}, err)
	})
	mux.HandleFunc("POST /v1/books/{id}/diff", s.diff)
	mux.HandleFunc("GET /v1/books/{id}/evidence-wall", s.loadEvidence)
	mux.HandleFunc("PUT /v1/books/{id}/evidence-wall", s.saveEvidence)
	mux.HandleFunc("POST /v1/shutdown", func(w http.ResponseWriter, r *http.Request) {
		send(w, map[string]bool{"closed": true})
		go s.Shutdown()
	})
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		token := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
		if subtle.ConstantTimeCompare([]byte(token), []byte(s.Token)) != 1 || r.Header.Get("Origin") != "" {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		if !strings.HasPrefix(r.Host, "127.0.0.1:") {
			http.Error(w, "invalid host", http.StatusForbidden)
			return
		}
		mux.ServeHTTP(w, r)
	})
}
func (s *Server) body(w http.ResponseWriter, r *http.Request, target any) error {
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, int64(s.Config.Limits.RequestMiB)*1024*1024))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return fmt.Errorf("請求格式或容量無效：%w", err)
	}
	var trailing any
	if err := decoder.Decode(&trailing); err != io.EOF {
		return fmt.Errorf("請求有多餘資料")
	}
	return nil
}
func send(w http.ResponseWriter, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	json.NewEncoder(w).Encode(value)
}
func respond(w http.ResponseWriter, value any, err error) {
	if err == nil {
		send(w, value)
		return
	}
	status := http.StatusBadRequest
	if errors.Is(err, library.ErrConflict) || errors.Is(err, design.ErrConflict) {
		status = http.StatusConflict
	} else if errors.Is(err, os.ErrNotExist) {
		status = http.StatusNotFound
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
}
