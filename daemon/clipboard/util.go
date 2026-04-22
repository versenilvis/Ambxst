package main

import (
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"strings"
	"sync"
)

func runShell(cmd string) error {
	return exec.Command("sh", "-c", cmd).Run()
}

// shellQuote wraps a string in single quotes, escaping any embedded single quotes
func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", "'\\''") + "'"
}


type RotatingWriter struct {
	path    string
	maxSize int64
	file    *os.File
	mu      sync.Mutex
}

func NewRotatingWriter(path string, maxSize int64) (*RotatingWriter, error) {
	w := &RotatingWriter{
		path:    path,
		maxSize: maxSize,
	}
	if err := w.open(); err != nil {
		return nil, err
	}
	return w, nil
}

func (w *RotatingWriter) open() error {
	f, err := os.OpenFile(w.path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return err
	}
	w.file = f
	return nil
}

func (w *RotatingWriter) Write(p []byte) (n int, err error) {
	w.mu.Lock()
	defer w.mu.Unlock()

	stat, err := w.file.Stat()
	if err == nil && stat.Size() > w.maxSize {
		w.file.Close()
		// truncate by opening with O_TRUNC
		f, err := os.OpenFile(w.path, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0644)
		if err != nil {
			return 0, fmt.Errorf("failed to rotate log: %w", err)
		}
		w.file = f
		w.file.WriteString("--- Log rotated ---\n")
	}

	return w.file.Write(p)
}

func (w *RotatingWriter) Close() error {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.file != nil {
		return w.file.Close()
	}
	return nil
}

// SetupLogging redirects log output to both stdout and a rotating file.
func SetupLogging(logPath string, maxSize int64, prefix string) (func(), error) {
	rw, err := NewRotatingWriter(logPath, maxSize)
	if err != nil {
		return nil, err
	}
	
	// Write to both file and stderr
	mw := io.MultiWriter(os.Stderr, rw)
	log.SetOutput(mw)
	log.SetPrefix(prefix)
	// format: date time.microseconds
	log.SetFlags(log.Ldate | log.Ltime | log.Lshortfile)
	
	return func() { rw.Close() }, nil
}
