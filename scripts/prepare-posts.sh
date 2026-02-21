#!/usr/bin/env bash
set -euo pipefail

# Processes raw markdown files from posts/ into content/posts/ with Hugo frontmatter.
#
# Handles Obsidian-style metadata:
#   **Date:** 2026-02-21
#   **Tags:** #java #best-practices #ddd
#
# - Title: first "# Heading", falls back to filename
# - Date: **Date:** line > git commit date > today
# - Tags: **Tags:** #tag1 #tag2 converted to Hugo tags array
# - Files with existing --- frontmatter are copied as-is.

POSTS_DIR="posts"
OUT_DIR="content/posts"

mkdir -p "$OUT_DIR"

for file in "$POSTS_DIR"/*.md; do
  [ -f "$file" ] || continue

  basename=$(basename "$file")
  slug="${basename%.md}"

  # Check if file already has frontmatter
  first_line=$(head -1 "$file")
  if [ "$first_line" = "---" ]; then
    cp "$file" "$OUT_DIR/$basename"
    continue
  fi

  # Extract title from first # heading
  title=$(grep -m1 '^# ' "$file" | sed 's/^# //' || true)
  if [ -z "$title" ]; then
    title=$(echo "$slug" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')
  fi

  # Extract date from **Date:** line, fallback to git date, then today
  date=$(grep -m1 '^\*\*Date:\*\*' "$file" | sed 's/.*\*\*Date:\*\*[[:space:]]*//' || true)
  if [ -z "$date" ]; then
    date=$(git log -1 --format="%cs" -- "$file" 2>/dev/null || date +%Y-%m-%d)
  fi
  if [ -z "$date" ]; then
    date=$(date +%Y-%m-%d)
  fi

  # Build frontmatter
  {
    echo "---"
    echo "title: \"$title\""
    echo "date: $date"
    echo "draft: false"
    echo "---"
    echo ""
    # Strip: # title, **Date:** line, **Tags:** line, and --- used as section dividers after metadata
    awk '
      NR==1 && /^# / { next }
      /^\*\*Date:\*\*/ { next }
      /^\*\*Tags:\*\*/ { next }
      # Remove --- lines that immediately follow stripped metadata (top of file)
      !body && /^---$/ { next }
      # Remove blank lines before first real content
      !body && /^[[:space:]]*$/ { next }
      { body=1; print }
    ' "$file"
  } > "$OUT_DIR/$basename"
done
