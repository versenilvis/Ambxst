package main

import (
	"bufio"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"os"
	"strings"
	"sync"
	"time"
)

// server listens on a unix socket and handles commands from QML.
// Protocol: newline-delimited JSON commands and responses.
//
// commands in:  {"cmd":"LIST"} / {"cmd":"DELETE","id":"5"} / etc.
// responses:    {"ok":true,"data":...} or {"ok":false,"error":"..."}
// push events:  {"event":"REFRESH_LIST"}
type server struct {
	db         *DB
	dataDir    string
	socketPath string

	mu      sync.Mutex
	clients []net.Conn
}

func newServer(db *DB, dataDir, socketPath string) *server {
	return &server{db: db, dataDir: dataDir, socketPath: socketPath}
}

func (s *server) broadcastItems() {
	items, err := s.db.List()
	if err != nil {
		log.Printf("broadcastItems: %v", err)
		return
	}
	msg, _ := json.Marshal(map[string]any{"event": "DATA", "items": items})
	msg = append(msg, '\n')

	s.mu.Lock()
	os.Stdout.Write(msg)
	s.mu.Unlock()

	s.mu.Lock()
	clients := make([]net.Conn, len(s.clients))
	copy(clients, s.clients)
	s.mu.Unlock()

	for _, c := range clients {
		c.Write(msg)
	}
}

func (s *server) run(ctx context.Context) error {
	go func() {
		select {
		case <-time.After(800 * time.Millisecond):
			s.broadcastItems()
		case <-ctx.Done():
		}
	}()

	if s.socketPath == "" {
		<-ctx.Done()
		return nil
	}

	os.Remove(s.socketPath)
	l, err := net.Listen("unix", s.socketPath)
	if err != nil {
		return fmt.Errorf("listen: %w", err)
	}
	defer l.Close()
	defer os.Remove(s.socketPath)

	log.Printf("listening on %s", s.socketPath)

	go func() {
		<-ctx.Done()
		l.Close()
	}()

	for {
		conn, err := l.Accept()
		if err != nil {
			if ctx.Err() != nil {
				return nil
			}
			return err
		}
		s.mu.Lock()
		s.clients = append(s.clients, conn)
		s.mu.Unlock()
		go s.handleConn(conn)
	}
}

func (s *server) removeClient(conn net.Conn) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i, c := range s.clients {
		if c == conn {
			s.clients = append(s.clients[:i], s.clients[i+1:]...)
			return
		}
	}
}

func (s *server) handleConn(conn net.Conn) {
	defer conn.Close()
	defer s.removeClient(conn)

	scanner := bufio.NewScanner(conn)
	scanner.Buffer(make([]byte, 4*1024*1024), 4*1024*1024)

	for scanner.Scan() {
		line := scanner.Text()
		if strings.TrimSpace(line) == "" {
			continue
		}
		resp := s.handleCommand(line)
		resp = append(resp, '\n')
		conn.Write(resp)
	}
}

type cmd struct {
	Cmd   string `json:"cmd"`
	ID    string `json:"id"`
	ID2   string `json:"id2"`
	Alias string `json:"alias"`
	ReqID string `json:"req_id"`
}

func (s *server) handleCommand(line string) []byte {
	var c cmd
	if err := json.Unmarshal([]byte(line), &c); err != nil {
		return errResp("invalid json: " + err.Error(), "")
	}

	var data any
	var err error

	switch c.Cmd {
	case "LIST":
		data, err = s.db.List()

	case "GET_CONTENT":
		data, err = s.db.GetFullContent(c.ID)

	case "DELETE":
		var hash string
		hash, err = s.db.Delete(c.ID)
		if err == nil && hash != "" {
			go clearSystemClipboardIfMatches(hash)
		}

	case "CLEAR":
		err = s.db.Clear()

	case "TOGGLE_PIN":
		err = s.db.TogglePin(c.ID)

	case "SET_ALIAS":
		err = s.db.SetAlias(c.ID, c.Alias)

	case "GET_IMAGE":
		var path, mime string
		path, mime, err = s.db.GetBinaryPath(c.ID)
		if err == nil {
			if path == "" {
				err = fmt.Errorf("no binary path")
			} else {
				var b []byte
				b, err = ReadImageFile(path, mime)
				if err == nil {
					encoded := base64.StdEncoding.EncodeToString(b)
					data = "data:" + mime + ";base64," + encoded
				}
			}
		}

	case "SWAP":
		err = s.db.SwapDisplayIndex(c.ID, c.ID2)

	case "COPY_TO_CLIPBOARD":
		var item *Item
		item, err = s.db.GetItem(c.ID)
		if err == nil && item != nil {
			if item.IsImage == 1 && item.BinaryPath != "" {
				go runShell("wl-copy --type " + item.MimeType + " < " + item.BinaryPath)
			} else {
				go runShell("printf '%s' " + shellQuote(item.FullContent) + " | wl-copy")
			}
		}

	case "PING":
		data = "pong"

	default:
		return errResp("unknown command: "+c.Cmd, c.ReqID)
	}

	if err != nil {
		return errResp(err.Error(), c.ReqID)
	}

	switch c.Cmd {
	case "DELETE", "CLEAR", "TOGGLE_PIN", "SET_ALIAS", "SWAP":
		go s.broadcastItems()
	}

	return okResp(data, c.ReqID)
}

func okResp(data any, reqID string) []byte {
	b, _ := json.Marshal(map[string]any{"ok": true, "data": data, "req_id": reqID})
	return b
}

func errResp(msg string, reqID string) []byte {
	b, _ := json.Marshal(map[string]any{"ok": false, "error": msg, "req_id": reqID})
	return b
}

func clearSystemClipboardIfMatches(hash string) {
	// check current clipboard hash before clearing
	cmd := fmt.Sprintf(
		`CURRENT=''; `+
			`if C=$(wl-paste --type text/plain 2>/dev/null); then CURRENT=$(echo -n "$C" | md5sum | cut -d' ' -f1); fi; `+
			`[ "$CURRENT" = '%s' ] && wl-copy --clear 2>/dev/null || true`,
		hash,
	)
	_ = runShell(cmd)
}
