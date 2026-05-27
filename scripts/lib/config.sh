#!/usr/bin/env bash
# config.sh — env loading and validation.
# shellcheck shell=bash

[[ -n "${LO_CONFIG_LOADED:-}" ]] && return 0
readonly LO_CONFIG_LOADED=1

# Load defaults first, then optional user override file.
# Order of precedence (lowest → highest):
#   1. defaults.env
#   2. $LO_CONFIG_FILE or config/server.env
#   3. existing environment (already exported by caller)
lo::config::load() {
  local defaults="${LO_CONFIG_DIR}/defaults.env"
  local custom="${LO_CONFIG_FILE:-${LO_CONFIG_DIR}/server.env}"

  if [[ -f "$defaults" ]]; then
    set -o allexport
    # shellcheck source=/dev/null
    . "$defaults"
    set +o allexport
  fi

  if [[ -f "$custom" ]]; then
    lo::log::info "loading config: $custom"
    set -o allexport
    # shellcheck source=/dev/null
    . "$custom"
    set +o allexport
  fi
}

# Fail fast if any of the named variables is empty.
lo::config::require() {
  local missing=()
  local var
  for var in "$@"; do
    if [[ -z "${!var:-}" ]]; then
      missing+=("$var")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    lo::die "missing required config: ${missing[*]} (see config/server.example.env)"
  fi
}

lo::config::print() {
  cat <<EOF
[config]
  INSTALL_DIR        = ${INSTALL_DIR:-(unset)}
  STEAM_USER         = ${STEAM_USER:-(unset)}
  STEAM_LINUX_APP_ID = ${STEAM_LINUX_APP_ID:-(unset)}
  SERVER_IDENTIFIER  = ${SERVER_IDENTIFIER:-(unset)}
  SERVER_IP_ADDRESS  = ${SERVER_IP_ADDRESS:-(unset)}
  SERVER_PORT        = ${SERVER_PORT:-(unset)}
  SERVER_QUERY_PORT  = ${SERVER_QUERY_PORT:-(unset)}
  SERVER_SLOTS       = ${SERVER_SLOTS:-(unset)}
  BACKUP_DIR         = ${BACKUP_DIR:-(unset)}
EOF
}
