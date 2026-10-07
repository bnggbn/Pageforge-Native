package api

import (
	"encoding/json"
	"errors"
	"io/fs"
	"net/http"

	"github.com/bnggbn/Pageforge-Native/backend/internal/fault"
)

type errorResponse struct {
	Code  fault.Code `json:"code"`
	Error string     `json:"error"`
}

func respond(w http.ResponseWriter, value any, err error) {
	if err == nil {
		send(w, value)
		return
	}
	code, found := fault.CodeOf(err)
	if !found {
		var path *fs.PathError
		switch {
		case errors.Is(err, fs.ErrNotExist):
			code = fault.NotFound
		case errors.As(err, &path):
			code = fault.StorageIO
		default:
			// Legacy business validators still share the generic validation code.
			code = fault.InvalidRequest
		}
	}
	message := err.Error()
	var coded *fault.Error
	if errors.As(err, &coded) {
		message = coded.Message
	}
	writeError(w, code, message)
}

func writeError(w http.ResponseWriter, code fault.Code, message string) {
	status := http.StatusInternalServerError
	switch code {
	case fault.InvalidRequest:
		status = http.StatusBadRequest
	case fault.UnsafePath:
		status, message = http.StatusBadRequest, "The storage path is invalid or contains a disallowed link."
	case fault.NotFound:
		status, message = http.StatusNotFound, "The requested resource was not found."
	case fault.Conflict:
		status = http.StatusConflict
	case fault.LimitExceeded:
		status, message = http.StatusRequestEntityTooLarge, "Content exceeds the configured size or structure limit."
	case fault.Unauthorized:
		status, message = http.StatusUnauthorized, "The request is not authenticated."
	case fault.Forbidden:
		status, message = http.StatusForbidden, "The request is not allowed."
	case fault.MethodNotAllowed:
		status, message = http.StatusMethodNotAllowed, "This resource does not support the request method."
	case fault.StorageMissing:
		message = "A required library file is missing. Check the files or backups."
	case fault.StorageCorrupt:
		message = "Library integrity verification failed. Check the files or backups."
	case fault.StorageIO:
		message = "Library I/O failed. Check storage space and permissions."
	case fault.UnsupportedStorage:
		message = "This library storage format requires a compatible application version."
	case fault.Internal:
		message = "The backend could not complete the request."
	default:
		code, message = fault.Internal, "The backend could not complete the request."
	}
	w.Header().Del("Content-Length")
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(errorResponse{Code: code, Error: message})
}

// Keep ServeMux's 404/405 contract (including Allow) while replacing plain text errors.
// Successful responses and redirects stream directly without buffering.
type routingErrors struct {
	http.ResponseWriter
	discard bool
}

func (w *routingErrors) WriteHeader(status int) {
	if (status == http.StatusNotFound || status == http.StatusMethodNotAllowed) &&
		w.Header().Get("Content-Type") != "application/json; charset=utf-8" {
		w.discard = true
		code := fault.NotFound
		if status == http.StatusMethodNotAllowed {
			code = fault.MethodNotAllowed
		}
		writeError(w.ResponseWriter, code, "")
		return
	}
	w.ResponseWriter.WriteHeader(status)
}

func (w *routingErrors) Write(data []byte) (int, error) {
	if w.discard {
		return len(data), nil
	}
	return w.ResponseWriter.Write(data)
}

func (w *routingErrors) Unwrap() http.ResponseWriter { return w.ResponseWriter }
