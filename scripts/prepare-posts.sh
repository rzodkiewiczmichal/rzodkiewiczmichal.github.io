#!/usr/bin/env bash
set -euo pipefail

# Processes raw markdown files from posts/ into content/posts/ with Hugo frontmatter.
# - Title: extracted from first "# Heading", falls back to filename
# - Date: git commit date of the file, falls back to current date
# - Slug: derived from filename
# Files that already have frontmatter (start with "---") are copied as-is.

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
    # Derive from filename: my-post-name -> My Post Name
    title=$(echo "$slug" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')
  fi

  # Get date from git (last commit that touched this file), fallback to today
  date=$(git log -1 --format="%cs" -- "$file" 2>/dev/null || date +%Y-%m-%d)
  if [ -z "$date" ]; then
    date=$(date +%Y-%m-%d)
  fi

  # Build the output file: frontmatter + content (strip the # title line if we extracted it)
  {
    echo "---"
    echo "title: \"$title\""
    echo "date: $date"
    echo "draft: false"
    echo "---"
    echo ""
    # If we pulled title from a heading, remove that first heading line from body
    if grep -q '^# ' "$file"; then
      awk '/^# / && !found { found=1; next } 1' "$file"
    else
      cat "$file"
    fi
  } > "$OUT_DIR/$basename"
done
