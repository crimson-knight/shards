#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_AMBER_CLI_PATH="$ROOT_DIR/../amber_cli"

UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/crystal-lang/shards.git}"
AMBER_CLI_REPO="${AMBER_CLI_REPO:-https://github.com/amberframework/amber_cli.git}"
AMBER_CLI_REF="${AMBER_CLI_REF:-main}"
AMBER_CLI_PATH="${AMBER_CLI_PATH:-}"
CRYSTAL_BIN="${CRYSTAL_BIN:-crystal}"
KEEP_WORKDIR="${KEEP_WORKDIR:-0}"
WORK_DIR="${WORK_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/shards-amber-compat.XXXXXX")}"

if [ -z "$AMBER_CLI_PATH" ] && [ -d "$DEFAULT_AMBER_CLI_PATH/.git" ]; then
  AMBER_CLI_PATH="$DEFAULT_AMBER_CLI_PATH"
fi

cleanup() {
  if [ "$KEEP_WORKDIR" = "1" ]; then
    printf '\nPreserving compatibility workspace at %s\n' "$WORK_DIR"
  else
    rm -rf "$WORK_DIR"
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

log_step() {
  printf '\n==> %s\n' "$1"
}

copy_tree() {
  local src="$1"
  local dest="$2"

  mkdir -p "$dest"
  tar \
    --exclude=".git" \
    --exclude="lib" \
    --exclude="bin" \
    --exclude=".shards" \
    --exclude="shard.lock" \
    -C "$src" -cf - . | tar -C "$dest" -xf -
}

normalize_lockfile() {
  local input="$1"
  local output="$2"

  sed \
    -e '/^# NOTICE:/d' \
    -e '/^version:/d' \
    -e '/^    checksum:/d' \
    "$input" > "$output"
}

install_with_shards() {
  local project_dir="$1"
  local bin_dir="$2"
  local home_dir="$3"

  rm -rf "$project_dir/lib" "$project_dir/.shards" "$project_dir/shard.lock"
  mkdir -p "$home_dir"

  (
    cd "$project_dir"
    HOME="$home_dir" PATH="$bin_dir:$PATH" shards install
  )
}

prepare_amber_cli_source() {
  local dest="$1"

  if [ -n "$AMBER_CLI_PATH" ]; then
    log_step "Copying local amber_cli checkout from $AMBER_CLI_PATH"
    copy_tree "$AMBER_CLI_PATH" "$dest"
  else
    log_step "Cloning amber_cli ($AMBER_CLI_REF) from GitHub"
    git clone --depth 1 --branch "$AMBER_CLI_REF" "$AMBER_CLI_REPO" "$dest"
  fi
}

build_upstream_shards() {
  local dest="$1"

  log_step "Cloning upstream crystal-lang/shards"
  git clone --depth 1 --branch master "$UPSTREAM_REPO" "$dest"

  log_step "Building upstream shards"
  make -C "$dest" clean bin/shards CRYSTAL="$CRYSTAL_BIN"
}

build_candidate_shards() {
  log_step "Building candidate shards fork"
  make -C "$ROOT_DIR" clean bin/shards-alpha bin/shards CRYSTAL="$CRYSTAL_BIN"
}

compare_lockfiles() {
  local label="$1"
  local baseline_lock="$2"
  local candidate_lock="$3"
  local normalized_dir="$WORK_DIR/normalized"

  mkdir -p "$normalized_dir"
  normalize_lockfile "$baseline_lock" "$normalized_dir/${label}.baseline.lock"
  normalize_lockfile "$candidate_lock" "$normalized_dir/${label}.candidate.lock"

  log_step "Comparing normalized lockfiles for $label"
  diff -u \
    "$normalized_dir/${label}.baseline.lock" \
    "$normalized_dir/${label}.candidate.lock"
}

build_amber_cli() {
  local amber_cli_dir="$1"
  local output_bin="$2"

  log_step "Building amber_cli with the candidate shards workflow"
  (
    cd "$amber_cli_dir"
    "$CRYSTAL_BIN" build src/amber_cli.cr -o "$output_bin"
  )
}

generate_smoke_app() {
  local amber_bin="$1"
  local output_dir="$2"

  log_step "Generating a fresh Amber smoke app"
  mkdir -p "$output_dir"
  (
    cd "$output_dir"
    "$amber_bin" new compat_smoke_app -y --no-deps
  )
}

build_generated_app() {
  local app_dir="$1"

  log_step "Compiling the generated Amber app"
  (
    cd "$app_dir"
    "$CRYSTAL_BIN" build "src/compat_smoke_app.cr" -o bin/compat_smoke_app
  )
}

main() {
  trap cleanup EXIT

  require_cmd git
  require_cmd make
  require_cmd tar
  require_cmd sed
  require_cmd diff
  require_cmd "$CRYSTAL_BIN"

  mkdir -p "$WORK_DIR"

  local upstream_dir="$WORK_DIR/upstream-shards"
  local amber_cli_source="$WORK_DIR/amber-cli-source"
  local amber_cli_baseline="$WORK_DIR/amber-cli-baseline"
  local amber_cli_candidate="$WORK_DIR/amber-cli-candidate"
  local amber_bin="$WORK_DIR/bin/amber"
  local generated_source_root="$WORK_DIR/generated"
  local generated_baseline="$WORK_DIR/generated-baseline"
  local generated_candidate="$WORK_DIR/generated-candidate"

  log_step "Compatibility workspace: $WORK_DIR"

  build_upstream_shards "$upstream_dir"
  build_candidate_shards
  prepare_amber_cli_source "$amber_cli_source"

  log_step "Resolving amber_cli dependencies with upstream shards"
  copy_tree "$amber_cli_source" "$amber_cli_baseline"
  install_with_shards "$amber_cli_baseline" "$upstream_dir/bin" "$WORK_DIR/home-upstream-amber-cli"

  log_step "Resolving amber_cli dependencies with the candidate shards fork"
  copy_tree "$amber_cli_source" "$amber_cli_candidate"
  install_with_shards "$amber_cli_candidate" "$ROOT_DIR/bin" "$WORK_DIR/home-candidate-amber-cli"

  compare_lockfiles \
    "amber_cli" \
    "$amber_cli_baseline/shard.lock" \
    "$amber_cli_candidate/shard.lock"

  mkdir -p "$(dirname "$amber_bin")"
  build_amber_cli "$amber_cli_candidate" "$amber_bin"
  generate_smoke_app "$amber_bin" "$generated_source_root"

  log_step "Resolving generated app dependencies with upstream shards"
  copy_tree "$generated_source_root/compat_smoke_app" "$generated_baseline"
  install_with_shards "$generated_baseline" "$upstream_dir/bin" "$WORK_DIR/home-upstream-generated"

  log_step "Resolving generated app dependencies with the candidate shards fork"
  copy_tree "$generated_source_root/compat_smoke_app" "$generated_candidate"
  install_with_shards "$generated_candidate" "$ROOT_DIR/bin" "$WORK_DIR/home-candidate-generated"

  compare_lockfiles \
    "generated_app" \
    "$generated_baseline/shard.lock" \
    "$generated_candidate/shard.lock"

  build_generated_app "$generated_candidate"

  printf '\nCompatibility validation passed.\n'
}

main "$@"
