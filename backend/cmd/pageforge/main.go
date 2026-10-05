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
	"time"

	"github.com/bnggbn/Pageforge-Native/backend/internal/api"
	"github.com/bnggbn/Pageforge-Native/backend/internal/config"
	"github.com/bnggbn/Pageforge-Native/backend/internal/library"
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
	c, err := config.Load(*root)
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
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt)
	defer cancel()
	application := api.New(store, c, cancel)
	server := &http.Server{Handler: application.Handler(), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 30 * time.Second, WriteTimeout: 30 * time.Second, IdleTimeout: 60 * time.Second}
	if *parentPipe {
		go func() { io.Copy(io.Discard, os.Stdin); cancel() }()
	}
	failure := make(chan error, 1)
	go func() { failure <- server.Serve(listener) }()
	// Only the parent reads this pipe. Do not put credentials in command line arguments or logs.
	if err = json.NewEncoder(os.Stdout).Encode(map[string]string{"origin": "http://" + listener.Addr().String(), "token": application.Token}); err != nil {
		return err
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
