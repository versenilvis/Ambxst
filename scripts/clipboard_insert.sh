#!/usr/bin/env bash
# Insert clipboard item into database
# Usage: clipboard_insert.sh <db_path> <hash> <mime_type> <is_image> <binary_path> <size>
# Content is read from stdin

set -euo pipefail

# Ensure UTF-8 locale for consistent character handling
export LC_ALL=C.UTF-8

DB_PATH="$1"
HASH="$2"
MIME_TYPE="$3"
IS_IMAGE="$4"
BINARY_PATH="$5"
SIZE="${6:-0}"

# Read content from stdin and strip carriage returns
# Use a temp file to preserve all unicode characters exactly
CONTENT_FILE=$(mktemp)
trap 'rm -f "$CONTENT_FILE"' EXIT
cat | tr -d '\r' >"$CONTENT_FILE"

# Read content back
CONTENT=$(cat "$CONTENT_FILE")

# Don't insert empty content for text items
if [ "$IS_IMAGE" = "0" ] && [ -z "$CONTENT" ]; then
	exit 0
fi

# Get timestamp in milliseconds
TIMESTAMP=$(date +%s)000

# Use a temp file to preserve all unicode characters exactly
trap 'rm -f "$CONTENT_FILE"' EXIT

# Use sqlite3 with -cmd to read from files using readfile() function
# This avoids all shell escaping issues
sqlite3 "$DB_PATH" <<EOSQL
.timeout 5000
BEGIN TRANSACTION;
-- Insert or update item (unpinned items always get display_index 0)
INSERT INTO clipboard_items 
(content_hash, mime_type, preview, full_content, is_image, binary_path, size, pinned, display_index, created_at, updated_at) 
VALUES (
    '${HASH}',
    '${MIME_TYPE}',
    CASE WHEN ${IS_IMAGE} = 1 THEN '[Image]' ELSE (
        CASE WHEN length(CAST(readfile('${CONTENT_FILE}') AS TEXT)) > 100 
        THEN substr(CAST(readfile('${CONTENT_FILE}') AS TEXT), 1, 97) || '...' 
        ELSE CAST(readfile('${CONTENT_FILE}') AS TEXT) 
        END
    ) END,
    readfile('${CONTENT_FILE}'),
    ${IS_IMAGE},
    '${BINARY_PATH}',
    ${SIZE},
    0,
    0,
    ${TIMESTAMP},
    ${TIMESTAMP}
)
ON CONFLICT(content_hash) DO UPDATE SET
updated_at = ${TIMESTAMP},
display_index = 0;
COMMIT;
EOSQL

# Signal that an insert happened
echo "REFRESH_LIST"
