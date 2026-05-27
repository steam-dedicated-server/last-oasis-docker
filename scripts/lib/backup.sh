#!/usr/bin/env bash
# backup.sh — save-data backup.
# shellcheck shell=bash

[[ -n "${LO_BACKUP_LOADED:-}" ]] && return 0
readonly LO_BACKUP_LOADED=1

lo::backup::create() {
  lo::config::require INSTALL_DIR
  local src="${INSTALL_DIR}/Mist/Saved"
  local dest="${BACKUP_DIR:-${INSTALL_DIR}/backups}"

  if [[ ! -d "$src" ]]; then
    lo::die "save directory not found: $src"
  fi

  install -d -m 0755 "$dest"
  local ts
  ts=$(date -u +%Y%m%dT%H%M%SZ)
  local archive="$dest/last-oasis-saved-${SERVER_IDENTIFIER:-server}-${ts}.tar.gz"

  lo::log::info "backing up ${src} → ${archive}"
  tar -C "${INSTALL_DIR}/Mist" -czf "$archive" Saved
  local size
  size=$(stat -c%s "$archive" 2>/dev/null || echo "?")
  lo::log::ok "backup complete: $archive (${size} bytes)"
}
