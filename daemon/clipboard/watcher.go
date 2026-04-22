package main

import (
	"bufio"
	"bytes"
	"context"
	"log"
	"os/exec"
	"strings"
	"syscall"
	"time"
)

// runWatcher watches the system clipboard and inserts new items into DB.
// It never exits until ctx is cancelled — goroutine restarts are handled internally.
func runWatcher(ctx context.Context, db *DB, dataDir string, onChange func()) {
	for {
		if ctx.Err() != nil {
			return
		}
		if err := watchOnce(ctx, db, dataDir, onChange); err != nil {
			if ctx.Err() != nil {
				return
			}
			log.Printf("watcher error: %v — restarting in 500ms", err)
			select {
			case <-ctx.Done():
				return
			case <-time.After(500 * time.Millisecond):
			}
		}
	}
}

// watchOnce runs wl-paste --watch and processes each clipboard change.
func watchOnce(ctx context.Context, db *DB, dataDir string, onChange func()) error {
	cmd := exec.CommandContext(ctx, "wl-paste", "--watch", "echo", "CLIPBOARD_CHANGE")
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	if err := cmd.Start(); err != nil {
		return err
	}

	go func() {
		<-ctx.Done()
		syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
	}()

	scanner := bufio.NewScanner(stdout)
	for scanner.Scan() {
		line := scanner.Text()
		if line != "CLIPBOARD_CHANGE" {
			continue
		}
		log.Println("clipboard change detected")
		inserted, err := checkAndInsert(ctx, db, dataDir)
		if err != nil {
			log.Printf("checkAndInsert error: %v", err)
			continue
		}
		if inserted {
			log.Println("new item inserted/updated")
			onChange()
		} else {
			log.Println("item already exists or empty")
		}
	}

	err = cmd.Wait()
	if ctx.Err() != nil {
		return nil
	}
	return err
}

// checkAndInsert inspects the current clipboard and inserts into DB.
// Returns true if a new item was inserted (not a duplicate).
func checkAndInsert(ctx context.Context, db *DB, dataDir string) (bool, error) {
	// 1. try file URI list
	if content, err := wlPaste(ctx, "text/uri-list"); err == nil && content != "" {
		content = strings.ReplaceAll(content, "\r", "")
		return db.InsertText(content, "text/uri-list")
	}

	// 2. try image types
	types, _ := wlPasteListTypes(ctx)
	for _, mime := range types {
		if !strings.HasPrefix(mime, "image/") {
			continue
		}
		data, err := wlPasteBytes(ctx, mime)
		if err != nil || len(data) == 0 {
			continue
		}
		return db.InsertImage(data, mime, dataDir)
	}

	// 3. plain text (prefer utf-8 charset)
	for _, mimeType := range []string{"text/plain;charset=utf-8", "text/plain"} {
		if content, err := wlPaste(ctx, mimeType); err == nil && content != "" {
			content = strings.ReplaceAll(content, "\r", "")
			return db.InsertText(content, "text/plain")
		}
	}

	return false, nil
}

func wlPaste(ctx context.Context, mimeType string) (string, error) {
	cmd := exec.CommandContext(ctx, "wl-paste", "--type", mimeType)
	out, err := cmd.Output()
	if err != nil {
		return "", err
	}
	return string(bytes.TrimRight(out, "\n")), nil
}

func wlPasteBytes(ctx context.Context, mimeType string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, "wl-paste", "--type", mimeType)
	return cmd.Output()
}

func wlPasteListTypes(ctx context.Context) ([]string, error) {
	cmd := exec.CommandContext(ctx, "wl-paste", "--list-types")
	out, err := cmd.Output()
	if err != nil {
		return nil, err
	}
	var types []string
	for _, line := range strings.Split(string(out), "\n") {
		line = strings.TrimSpace(line)
		if line != "" {
			types = append(types, line)
		}
	}
	return types, nil
}
