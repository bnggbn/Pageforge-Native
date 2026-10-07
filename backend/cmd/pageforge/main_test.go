package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func isolatedRoot(t *testing.T) string {
	t.Helper()
	t.Setenv("PAGEFORGE_LIBRARY_ROOT", "")
	root := t.TempDir()
	data, err := os.ReadFile("../../../pageforge.config.json")
	if err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(filepath.Join(root, "pageforge.config.json"), data, 0600); err != nil {
		t.Fatal(err)
	}
	return root
}

func assertReleased(t *testing.T, root, origin string) {
	t.Helper()
	if _, err := os.Stat(filepath.Join(root, "library", ".pageforge", "server.lock")); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("library lock remains: %v", err)
	}
	u, err := url.Parse(origin)
	if err != nil {
		t.Fatal("invalid readiness origin")
	}
	conn, err := net.DialTimeout("tcp", u.Host, 100*time.Millisecond)
	if err == nil {
		conn.Close()
		t.Fatal("listener remains open")
	}
}

func TestShutdownReleasesLibraryAndListener(t *testing.T) {
	root := isolatedRoot(t)
	for _, mode := range []string{"parent EOF", "context cancellation", "restart"} {
		t.Run(mode, func(t *testing.T) {
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			parent, pipe := io.Pipe()
			defer parent.Close()
			defer pipe.Close()
			reader, ready := io.Pipe()
			defer reader.Close()
			defer ready.Close()
			done := make(chan error, 1)
			go func() { done <- serve(ctx, root, parent, ready); ready.Close() }()
			frame := make(chan []byte, 1)
			go func() { line, _ := bufio.NewReader(reader).ReadBytes('\n'); frame <- line }()
			var info struct{ Origin, Token string }
			select {
			case data := <-frame:
				if err := json.Unmarshal(data, &info); err != nil {
					t.Fatal("invalid readiness frame")
				}
			case <-time.After(5 * time.Second):
				t.Fatal("readiness timed out")
			}
			client := &http.Client{Timeout: time.Second}
			request, _ := http.NewRequest("GET", info.Origin+"/v1/status", nil)
			response, err := client.Do(request)
			if err != nil {
				t.Fatal(err)
			}
			response.Body.Close()
			if response.StatusCode != http.StatusUnauthorized {
				t.Fatalf("unauthenticated status: %d", response.StatusCode)
			}
			request.Header.Set("Authorization", "Bearer "+info.Token)
			response, err = client.Do(request)
			if err != nil {
				t.Fatal(err)
			}
			response.Body.Close()
			if response.StatusCode != http.StatusOK {
				t.Fatalf("authenticated status: %d", response.StatusCode)
			}
			client.CloseIdleConnections()
			if mode == "context cancellation" {
				cancel()
			} else {
				pipe.Close()
			}
			select {
			case err := <-done:
				if err != nil {
					t.Fatal(err)
				}
			case <-time.After(5 * time.Second):
				t.Fatal("shutdown timed out")
			}
			assertReleased(t, root, info.Origin)
		})
	}
}

type failedAnnouncement struct {
	origin string
	err    error
}

func (w *failedAnnouncement) Write(data []byte) (int, error) {
	var info struct{ Origin string }
	_ = json.Unmarshal(data, &info)
	w.origin = info.Origin
	return 0, w.err
}
func TestAnnouncementFailureReleasesResources(t *testing.T) {
	root := isolatedRoot(t)
	failure := &failedAnnouncement{err: errors.New("parent readiness pipe closed")}
	err := serve(context.Background(), root, nil, failure)
	if !errors.Is(err, failure.err) {
		t.Fatalf("lost announcement error: %v", err)
	}
	assertReleased(t, root, failure.origin)
}
