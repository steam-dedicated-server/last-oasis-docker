#!/usr/bin/env bash
# common.sh — logging, retries, basic utilities.
# Sourced by scripts/lo. Do NOT enable `set -e` here; the caller decides.
# shellcheck shell=bash

[[ -n "${LO_COMMON_LOADED:-}" ]] && return 0
readonly LO_COMMON_LOADED=1

# ---------- Colors (only when stderr is a TTY) ----------
if [[ -t 2 ]]; then
  readonly LO_RED=$'\033[31m'
  readonly LO_YELLOW=$'\033[33m'
  readonly LO_GREEN=$'\033[32m'
  readonly LO_BLUE=$'\033[34m'
  readonly LO_DIM=$'\033[2m'
  readonly LO_RESET=$'\033[0m'
else
  readonly LO_RED=''  LO_YELLOW=''  LO_GREEN=''  LO_BLUE=''  LO_DIM=''  LO_RESET=''
fi

# ---------- Logging ----------
lo::log::_write() {
  local level=$1 color=$2 msg=$3
  printf '%s[%s]%s %s%-5s%s %s\n' \
    "$LO_DIM" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$LO_RESET" \
    "$color" "$level" "$LO_RESET" \
    "$msg" >&2
}

lo::log::debug() {
  if [[ "${LO_LOG_LEVEL:-info}" == "debug" ]]; then
    lo::log::_write DEBUG "$LO_DIM" "$*"
  fi
}

lo::log::info()  { lo::log::_write INFO  "$LO_BLUE"   "$*"; }
lo::log::warn()  { lo::log::_write WARN  "$LO_YELLOW" "$*"; }
lo::log::error() { lo::log::_write ERROR "$LO_RED"    "$*"; }
lo::log::ok()    { lo::log::_write OK    "$LO_GREEN"  "$*"; }

lo::die() {
  lo::log::error "$*"
  exit 1
}

# ---------- Retry with exponential backoff ----------
# Usage: lo::retry <cmd> [args...]
# Tunable via LO_RETRY_MAX (default 5) and LO_RETRY_DELAY (default 2s, doubles).
lo::retry() {
  local max=${LO_RETRY_MAX:-5}
  local delay=${LO_RETRY_DELAY:-2}
  local attempt=1
  local rc=0
  while (( attempt <= max )); do
    if "$@"; then return 0; fi
    rc=$?
    if (( attempt == max )); then break; fi
    lo::log::warn "attempt ${attempt}/${max} failed (rc=${rc}); retrying in ${delay}s"
    sleep "$delay"
    delay=$(( delay * 2 ))
    attempt=$(( attempt + 1 ))
  done
  lo::log::error "all ${max} attempts failed"
  return "$rc"
}

# ---------- Require external commands ----------
lo::require() {
  local missing=()
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
  done
  if (( ${#missing[@]} > 0 )); then
    lo::die "missing required commands: ${missing[*]}"
  fi
}

# ---------- Help ----------
lo::help() {
  cat <<'EOF'
lo — Last Oasis dedicated server CLI

Usage: lo <command> [args...]

Server lifecycle:
  install         Download / install the dedicated server (validates files)
  update          Update the dedicated server to the latest build
  validate        Re-validate game files via steamcmd
  run, start      Start the dedicated server in the foreground
  health          Run A2S healthcheck against SERVER_QUERY_PORT

Steam:
  login           Interactive steamcmd login (only for non-anonymous accounts)

Operations:
  backup          Tar+gzip Mist/Saved/ into BACKUP_DIR
  config          Print effective configuration
  shell           Drop into an interactive bash
  version         Print version
  help            Show this help

Environment:
  See config/server.example.env for the full list of variables.
EOF
}
