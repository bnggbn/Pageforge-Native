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
		status, message = http.StatusBadRequest, "資料路徑無效或包含不允許的連結。"
	case fault.NotFound:
		status, message = http.StatusNotFound, "找不到要求的資源。"
	case fault.Conflict:
		status = http.StatusConflict
	case fault.LimitExceeded:
		status, message = http.StatusRequestEntityTooLarge, "內容超過設定容量或結構上限。"
	case fault.Unauthorized:
		status, message = http.StatusUnauthorized, "請求未通過驗證。"
	case fault.Forbidden:
		status, message = http.StatusForbidden, "此請求不被允許。"
	case fault.MethodNotAllowed:
		status, message = http.StatusMethodNotAllowed, "此資源不支援這個請求方式。"
	case fault.StorageMissing:
		message = "書庫依賴檔案缺失，請檢查檔案或備份。"
	case fault.StorageCorrupt:
		message = "書庫內容驗證失敗，請檢查檔案或備份。"
	case fault.StorageIO:
		message = "書庫讀寫失敗，請檢查儲存空間與權限。"
	case fault.UnsupportedStorage:
		message = "此書庫儲存格式尚不支援，請使用相容版本。"
	case fault.Internal:
		message = "後端處理失敗。"
	default:
		code, message = fault.Internal, "後端處理失敗。"
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
