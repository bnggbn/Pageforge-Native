package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"time"

	"github.com/bnggbn/Pageforge-Native/backend/internal/api"
	"github.com/bnggbn/Pageforge-Native/backend/internal/config"
	"github.com/bnggbn/Pageforge-Native/backend/internal/library"
	"github.com/bnggbn/Pageforge-Native/backend/internal/settings"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
func run() error {
	root := flag.String("root", ".", "project/config directory")
	parentPipe := flag.Bool("parent-pipe", false, "exit when parent closes stdin")
	flag.Parse()
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	var parent io.Reader
	if *parentPipe {
		parent = os.Stdin
	}
	return serve(ctx, *root, parent, os.Stdout)
}

// serve owns the library, listener and server until shutdown has completed.
func serve(ctx context.Context, root string, parent io.Reader, ready io.Writer) error {
	c, err := config.Load(root)
	if err != nil {
		return err
	}
	store, err := library.Open(c)
	if err != nil {
		return err
	}
	defer store.Close()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return err
	}
	defer listener.Close()
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	application := api.New(store, c, cancel)
	application.ClientSettings = settings.New(
		filepath.Join(root, "pageforge.design.json"),
		filepath.Join(root, "pageforge.design.local.json"), 16*1024,
	)
	server := &http.Server{
		Handler:           application.Handler(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}
	defer server.Close()
	failure := make(chan error, 1)
	go func() { failure <- server.Serve(listener) }()
	// Only the parent reads this pipe. Never log or echo the readiness token.
	if err = json.NewEncoder(ready).Encode(map[string]string{
		"origin": "http://" + listener.Addr().String(), "token": application.Token,
	}); err != nil {
		return fmt.Errorf("announce readiness: %w", err)
	}
	if parent != nil {
		go func() { io.Copy(io.Discard, parent); cancel() }()
	}
	select {
	case <-ctx.Done():
	case err = <-failure:
		if err != http.ErrServerClosed {
			return err
		}
	}
	shutdown, stop := context.WithTimeout(context.Background(), 3*time.Second)
	defer stop()
	return server.Shutdown(shutdown)
}
