package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
)

func main() {
	dbPath := flag.String("db", "", "")
	dataDir := flag.String("data", "", "")
	socketPath := flag.String("socket", "/tmp/ambxst-clipboard.sock", "")
	logPath := flag.String("log", "", "")
	maxLogSize := flag.Int64("maxlog", 5*1024*1024, "")
	cmd := flag.String("cmd", "", "send JSON command to running daemon and exit")
	flag.Parse()

	if *cmd != "" {
		if err := sendCmd(*socketPath, *cmd); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		return
	}

	if *dbPath == "" || *dataDir == "" {
		flag.Usage()
		os.Exit(1)
	}

	if *logPath != "" {
		cleanup, err := SetupLogging(*logPath, *maxLogSize, "[Clipboard] ")
		if err != nil {
			log.Printf("warning: failed to setup log file: %v", err)
		} else {
			defer cleanup()
		}
	} else {
		log.SetFlags(log.Ldate | log.Ltime | log.Lshortfile)
	}

	log.Printf("ambxst-clipboard starting db=%s socket=%s", *dbPath, *socketPath)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigs
		cancel()
	}()

	if err := os.MkdirAll(filepath.Dir(*dbPath), 0755); err != nil {
		log.Fatalf("failed to create db directory: %v", err)
	}

	db, err := newDB(*dbPath)
	if err != nil {
		log.Fatalf("failed to open db: %v", err)
	}
	defer db.Close()

	if err := os.MkdirAll(*dataDir, 0755); err != nil {
		log.Fatalf("failed to create data dir: %v", err)
	}

	srv := newServer(db, *dataDir, *socketPath)

	watcherDone := make(chan struct{})
	go func() {
		defer close(watcherDone)
		runWatcher(ctx, db, *dataDir, func() {
			srv.broadcastItems()
		})
	}()

	if err := srv.run(ctx); err != nil {
		log.Printf("server error: %v", err)
	}

	<-watcherDone
	log.Println("shutdown complete")
}

func sendCmd(socketPath, cmd string) error {
	conn, err := net.Dial("unix", socketPath)
	if err != nil {
		return err
	}
	defer conn.Close()
	fmt.Fprintln(conn, cmd)
	if uc, ok := conn.(*net.UnixConn); ok {
		uc.CloseWrite()
	}
	io.Copy(os.Stdout, conn)
	return nil
}
