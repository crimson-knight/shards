#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${DOCS_OUTPUT_DIR:-site}"
PROJECT_NAME="${DOCS_PROJECT_NAME:-Ashard}"
PROJECT_VERSION="${DOCS_PROJECT_VERSION:-$(cat "$ROOT_DIR/VERSION")}"
SOURCE_REFNAME="${DOCS_SOURCE_REFNAME:-$(git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD)}"
SOURCE_URL_PATTERN="${DOCS_SOURCE_URL_PATTERN:-}"
CANONICAL_BASE_URL="${DOCS_CANONICAL_BASE_URL:-https://crimson-knight.github.io/shards}"
BASE_PATH="${DOCS_BASE_PATH:-/shards}"

if [ -z "$SOURCE_URL_PATTERN" ]; then
  SOURCE_URL_PATTERN='https://github.com/crimson-knight/shards/blob/%{refname}/%{path}#L%{line}'
fi

cd "$ROOT_DIR"
rm -rf "$OUTPUT_DIR"

crystal run src/shards.cr -- docs \
  --output "$OUTPUT_DIR" \
  --project-name="$PROJECT_NAME" \
  --project-version="$PROJECT_VERSION" \
  --source-refname="$SOURCE_REFNAME" \
  --source-url-pattern="$SOURCE_URL_PATTERN" \
  --canonical-base-url="$CANONICAL_BASE_URL" \
  --base-path="$BASE_PATH"

touch "$OUTPUT_DIR/.nojekyll"
