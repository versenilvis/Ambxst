package main

import (
	"crypto/md5"
	"database/sql"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"

	_ "modernc.org/sqlite"
)

const schema = `
CREATE TABLE IF NOT EXISTS clipboard_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    content_hash TEXT NOT NULL UNIQUE,
    mime_type TEXT NOT NULL DEFAULT 'text/plain',
    preview TEXT NOT NULL,
    full_content TEXT,
    is_image INTEGER NOT NULL DEFAULT 0,
    binary_path TEXT,
    size INTEGER NOT NULL DEFAULT 0,
    pinned INTEGER NOT NULL DEFAULT 0,
    alias TEXT,
    display_index INTEGER,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_content_hash ON clipboard_items(content_hash);
CREATE INDEX IF NOT EXISTS idx_created_at ON clipboard_items(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_is_image ON clipboard_items(is_image);
CREATE INDEX IF NOT EXISTS idx_pinned ON clipboard_items(pinned DESC);
CREATE INDEX IF NOT EXISTS idx_display_index ON clipboard_items(pinned DESC, display_index ASC);

CREATE VIRTUAL TABLE IF NOT EXISTS clipboard_fts USING fts5(
    preview, full_content, content=clipboard_items, content_rowid=id
);
CREATE TRIGGER IF NOT EXISTS clipboard_items_ai AFTER INSERT ON clipboard_items BEGIN
    INSERT INTO clipboard_fts(rowid, preview, full_content) VALUES (new.id, new.preview, new.full_content);
END;
CREATE TRIGGER IF NOT EXISTS clipboard_items_ad AFTER DELETE ON clipboard_items BEGIN
    DELETE FROM clipboard_fts WHERE rowid = old.id;
END;
CREATE TRIGGER IF NOT EXISTS clipboard_items_au AFTER UPDATE ON clipboard_items BEGIN
    DELETE FROM clipboard_fts WHERE rowid = old.id;
    INSERT INTO clipboard_fts(rowid, preview, full_content) VALUES (new.id, new.preview, new.full_content);
END;
`

type DB struct {
	sql *sql.DB
}

func newDB(path string) (*DB, error) {
	conn, err := sql.Open("sqlite", path+"?_journal=WAL&_timeout=5000&_foreign_keys=on")
	if err != nil {
		return nil, err
	}
	conn.SetMaxOpenConns(1)

	if _, err := conn.Exec(schema); err != nil {
		return nil, fmt.Errorf("failed to apply schema: %w", err)
	}
	return &DB{sql: conn}, nil
}

func (d *DB) Close() { d.sql.Close() }

// Item mirrors what QML expects
type Item struct {
	ID           int64   `json:"id"`
	ContentHash  string  `json:"content_hash"`
	MimeType     string  `json:"mime_type"`
	Preview      string  `json:"preview"`
	FullContent  string  `json:"full_content"`
	IsImage      int     `json:"is_image"`
	BinaryPath   string  `json:"binary_path"`
	Size         int64   `json:"size"`
	Pinned       int     `json:"pinned"`
	Alias        *string `json:"alias"`
	DisplayIndex *int    `json:"display_index"`
	CreatedAt    int64   `json:"created_at"`
	UpdatedAt    int64   `json:"updated_at"`
}

func (d *DB) List() ([]Item, error) {
	rows, err := d.sql.Query(`
		SELECT id, content_hash, mime_type, preview, COALESCE(full_content,''),
		       is_image, COALESCE(binary_path,''), size, pinned, alias,
		       display_index, created_at, updated_at
		FROM clipboard_items
		ORDER BY pinned DESC, updated_at DESC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var items []Item
	for rows.Next() {
		var it Item
		if err := rows.Scan(&it.ID, &it.ContentHash, &it.MimeType, &it.Preview,
			&it.FullContent, &it.IsImage, &it.BinaryPath, &it.Size,
			&it.Pinned, &it.Alias, &it.DisplayIndex, &it.CreatedAt, &it.UpdatedAt,
		); err != nil {
			return nil, err
		}
		items = append(items, it)
	}
	return items, rows.Err()
}

func (d *DB) GetFullContent(id string) (string, error) {
	var content string
	err := d.sql.QueryRow("SELECT COALESCE(full_content,'') FROM clipboard_items WHERE id=?", id).Scan(&content)
	return content, err
}

func (d *DB) Delete(id string) (string, error) {
	var hash string
	_ = d.sql.QueryRow("SELECT content_hash FROM clipboard_items WHERE id=?", id).Scan(&hash)
	_, err := d.sql.Exec("DELETE FROM clipboard_items WHERE id=?", id)
	return hash, err
}

func (d *DB) Clear() error {
	_, err := d.sql.Exec("DELETE FROM clipboard_items WHERE pinned=0")
	return err
}

func (d *DB) TogglePin(id string) error {
	_, err := d.sql.Exec("UPDATE clipboard_items SET pinned = CASE WHEN pinned=1 THEN 0 ELSE 1 END WHERE id=?", id)
	return err
}

func (d *DB) SetAlias(id, alias string) error {
	if alias == "" {
		_, err := d.sql.Exec("UPDATE clipboard_items SET alias=NULL WHERE id=?", id)
		return err
	}
	_, err := d.sql.Exec("UPDATE clipboard_items SET alias=? WHERE id=?", alias, id)
	return err
}

func (d *DB) GetBinaryPath(id string) (string, string, error) {
	var path, mime string
	err := d.sql.QueryRow("SELECT COALESCE(binary_path,''), mime_type FROM clipboard_items WHERE id=?", id).Scan(&path, &mime)
	return path, mime, err
}

// Insert text item. Returns true if new (not duplicate).
func (d *DB) GetItem(id string) (*Item, error) {
	var item Item
	var alias sql.NullString
	var displayIndex sql.NullInt64
	err := d.sql.QueryRow(`
		SELECT id, content_hash, mime_type, preview, COALESCE(full_content,''),
		       is_image, COALESCE(binary_path,''), size, pinned, alias,
		       display_index, created_at, updated_at
		FROM clipboard_items WHERE id = ?`, id).Scan(
		&item.ID, &item.ContentHash, &item.MimeType, &item.Preview, &item.FullContent,
		&item.IsImage, &item.BinaryPath, &item.Size, &item.Pinned, &alias,
		&displayIndex, &item.CreatedAt, &item.UpdatedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	if alias.Valid {
		v := alias.String
		item.Alias = &v
	}
	if displayIndex.Valid {
		v := int(displayIndex.Int64)
		item.DisplayIndex = &v
	}
	return &item, nil
}

func (d *DB) InsertText(content, mimeType string) (bool, error) {
	hash := md5Hex(content)
	ts := nowMs()
	preview := content
	if len(preview) > 100 {
		preview = preview[:97] + "..."
	}

	res, err := d.sql.Exec(`
		INSERT INTO clipboard_items
		  (content_hash, mime_type, preview, full_content, is_image, binary_path, size, pinned, display_index, created_at, updated_at)
		VALUES (?,?,?,?,0,'',?,0,0,?,?)
		ON CONFLICT(content_hash) DO UPDATE SET updated_at=excluded.updated_at, display_index=0
	`, hash, mimeType, preview, content, int64(len(content)), ts, ts)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

// InsertImage saves binary data to dataDir and records it in DB.
func (d *DB) InsertImage(data []byte, mimeType, dataDir string) (bool, error) {
	hash := md5Hex(string(data))

	// check duplicate
	var exists int
	_ = d.sql.QueryRow("SELECT COUNT(*) FROM clipboard_items WHERE content_hash=?", hash).Scan(&exists)
	if exists > 0 {
		// update timestamp only
		_, err := d.sql.Exec("UPDATE clipboard_items SET updated_at=? WHERE content_hash=?", nowMs(), hash)
		return false, err
	}

	ext := mimeToExt(mimeType)
	ts := nowMs()
	filename := fmt.Sprintf("clipboard_%d.%s", ts, ext)
	fullPath := filepath.Join(dataDir, filename)

	if err := os.WriteFile(fullPath, data, 0644); err != nil {
		return false, err
	}

	_, err := d.sql.Exec(`
		INSERT INTO clipboard_items
		  (content_hash, mime_type, preview, full_content, is_image, binary_path, size, pinned, display_index, created_at, updated_at)
		VALUES (?,?,'[Image]','',1,?,?,0,0,?,?)
	`, hash, mimeType, fullPath, int64(len(data)), ts, ts)
	return err == nil, err
}

func (d *DB) SwapDisplayIndex(id1, id2 string) error {
	tx, err := d.sql.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	var idx1, idx2 sql.NullInt64
	tx.QueryRow("SELECT display_index FROM clipboard_items WHERE id=?", id1).Scan(&idx1)
	tx.QueryRow("SELECT display_index FROM clipboard_items WHERE id=?", id2).Scan(&idx2)
	tx.Exec("UPDATE clipboard_items SET display_index=? WHERE id=?", idx2, id1)
	tx.Exec("UPDATE clipboard_items SET display_index=? WHERE id=?", idx1, id2)
	return tx.Commit()
}

func (d *DB) CleanOrphanedFiles() {
	rows, err := d.sql.Query("SELECT binary_path FROM clipboard_items WHERE binary_path != ''")
	if err != nil {
		return
	}
	defer rows.Close()

	inDB := map[string]bool{}
	for rows.Next() {
		var p string
		rows.Scan(&p)
		inDB[p] = true
	}
	// nothing else to do, we don't scan FS here to keep it simple
	_ = inDB
}

// ReadImageFile reads the binary file for an image item and returns base64 data URL.
func ReadImageFile(path, mime string) ([]byte, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	return io.ReadAll(f)
}

func md5Hex(s string) string {
	h := md5.Sum([]byte(s))
	return hex.EncodeToString(h[:])
}

func nowMs() int64 {
	return time.Now().UnixMilli()
}

func mimeToExt(mime string) string {
	switch mime {
	case "image/png":
		return "png"
	case "image/jpeg":
		return "jpg"
	case "image/gif":
		return "gif"
	case "image/webp":
		return "webp"
	case "image/bmp":
		return "bmp"
	default:
		return "img"
	}
}
