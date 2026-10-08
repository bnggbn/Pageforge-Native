// Package fault defines transport-independent error codes. Messages are for people;
// callers must use CodeOf/errors.Is rather than parsing those messages.
package fault

import (
	"encoding/json"
	"errors"
	"io"
	"io/fs"

	"github.com/bnggbn/vax-action-history/storage"
)

type Code string

const (
	InvalidRequest     Code = "INVALID_REQUEST"
	NotFound           Code = "NOT_FOUND"
	Conflict           Code = "CONFLICT"
	LimitExceeded      Code = "LIMIT_EXCEEDED"
	StorageCorrupt     Code = "STORAGE_CORRUPT"
	StorageMissing     Code = "STORAGE_MISSING"
	StorageIO          Code = "STORAGE_IO"
	UnsupportedStorage Code = "UNSUPPORTED_STORAGE"
	UnsafePath         Code = "UNSAFE_PATH"
	Internal           Code = "INTERNAL_ERROR"
	Unauthorized       Code = "UNAUTHORIZED"
	Forbidden          Code = "FORBIDDEN"
	MethodNotAllowed   Code = "METHOD_NOT_ALLOWED"
)

type Error struct {
	Code    Code
	Message string
	cause   error
}

func (e *Error) Error() string {
	if e.cause == nil {
		return e.Message
	}
	return e.Message + ": " + e.cause.Error()
}

func (e *Error) Unwrap() error { return e.cause }

func New(code Code, message string) error { return &Error{Code: code, Message: message} }

func Wrap(code Code, message string, cause error) error {
	if cause == nil {
		return nil
	}
	return &Error{Code: code, Message: message, cause: cause}
}

// Ensure adds a boundary classification only when the source has no code yet.
func Ensure(code Code, message string, cause error) error {
	if cause == nil {
		return nil
	}
	if _, found := CodeOf(cause); found {
		return cause
	}
	return Wrap(code, message, cause)
}

func CodeOf(err error) (Code, bool) {
	var coded *Error
	if errors.As(err, &coded) {
		return coded.Code, true
	}
	var objectError *storage.Error
	if errors.As(err, &objectError) {
		switch objectError.Kind {
		case storage.InvalidInput:
			return InvalidRequest, true
		case storage.InvalidOptions:
			return Internal, true
		case storage.LimitExceeded:
			return LimitExceeded, true
		case storage.Corrupt:
			return StorageCorrupt, true
		case storage.Missing:
			return StorageMissing, true
		case storage.IO:
			return StorageIO, true
		case storage.UnsupportedFormat:
			return UnsupportedStorage, true
		case storage.UnsafePath:
			return UnsafePath, true
		default:
			return Internal, true
		}
	}
	return "", false
}

// Read is for required storage dependencies. Absence is not a missing API resource.
func Read(err error) error {
	if err == nil {
		return nil
	}
	if _, found := CodeOf(err); found {
		return err
	}
	if errors.Is(err, fs.ErrNotExist) {
		return Wrap(StorageMissing, "required library dependency is missing", err)
	}
	var syntax *json.SyntaxError
	var value *json.UnmarshalTypeError
	if errors.Is(err, io.EOF) || errors.Is(err, io.ErrUnexpectedEOF) ||
		errors.As(err, &syntax) || errors.As(err, &value) {
		return Wrap(StorageCorrupt, "library data is corrupt", err)
	}
	return Wrap(StorageIO, "could not read library data", err)
}

func Write(err error) error { return Ensure(StorageIO, "could not save library data", err) }

func Encode(err error) error { return Ensure(Internal, "could not encode storage data", err) }
