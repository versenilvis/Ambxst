#!/usr/bin/env bash
# High-accuracy OCR script for Ambxst (Vietnamese + English)
set -eo pipefail

TESS_DIR="${HOME}/.local/share/tessdata"
LANGS="vie+eng"

IMAGE_INPUT="${1:-}"
TEMP_DIR="/tmp/ambxst_ocr"
mkdir -p "$TEMP_DIR"
RAW_IMG="$TEMP_DIR/raw.png"
PROC_IMG="$TEMP_DIR/proc.png"

if [ -n "$IMAGE_INPUT" ] && [ -f "$IMAGE_INPUT" ]; then
    cp "$IMAGE_INPUT" "$RAW_IMG"
else
    # Let user select region on screen
    COORDS=$(slurp 2>/dev/null || true)
    if [ -z "$COORDS" ]; then
        exit 0
    fi
    grim -g "$COORDS" "$RAW_IMG"
fi

# Preprocessing with ImageMagick for highest character recognition accuracy
# - Resample/scale 200% with Mitchell filter
# - Convert to grayscale
# - Sharpen edges with unsharp mask
if command -v magick >/dev/null 2>&1; then
    magick "$RAW_IMG" -colorspace Gray -filter Mitchell -resize 200% -unsharp 1.5x1+0.7+0.02 "$PROC_IMG"
elif command -v convert >/dev/null 2>&1; then
    convert "$RAW_IMG" -colorspace Gray -filter Mitchell -resize 200% -unsharp 1.5x1+0.7+0.02 "$PROC_IMG"
else
    cp "$RAW_IMG" "$PROC_IMG"
fi

TESS_ARGS=("-l" "$LANGS")
if [ -d "$TESS_DIR" ] && [ -f "$TESS_DIR/vie.traineddata" ]; then
    TESS_ARGS+=("--tessdata-dir" "$TESS_DIR")
fi

# Run tesseract with PSM 6 (single uniform block) or fallback to PSM 3 (auto)
TEXT=$(tesseract "$PROC_IMG" stdout "${TESS_ARGS[@]}" --psm 6 2>/dev/null || true)
if [ -z "$(echo "$TEXT" | tr -d '[:space:]')" ]; then
    TEXT=$(tesseract "$PROC_IMG" stdout "${TESS_ARGS[@]}" --psm 3 2>/dev/null || true)
fi

TRIMMED_TEXT=$(echo "$TEXT" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

if [ -n "$TRIMMED_TEXT" ]; then
    echo -n "$TRIMMED_TEXT" | wl-copy
    SHORT_PREVIEW=$(echo "$TRIMMED_TEXT" | head -n 3 | cut -c 1-80)
    notify-send "OCR Result" "Text copied to clipboard:\n$SHORT_PREVIEW" -i edit-paste -t 4000
    echo "$TRIMMED_TEXT"
else
    notify-send "OCR Result" "No text detected in selected area" -u low -i dialogue-error -t 3000
fi
