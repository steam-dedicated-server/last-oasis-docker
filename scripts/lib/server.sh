#!/usr/bin/env bash
# server.sh — dedicated server lifecycle.
# shellcheck shell=bash

[[ -n "${LO_SERVER_LOADED:-}" ]] && return 0
readonly LO_SERVER_LOADED=1

lo::server::_binary() {
  printf '%s/Mist/Binaries/Linux/MistServer-Linux-Shipping' "$INSTALL_DIR"
}

lo::server::_assert_installed() {
  local bin
  bin=$(lo::server::_binary)
  if [[ ! -x "$bin" ]]; then
    lo::die "server binary not found at $bin — run 'lo install' first"
  fi
}

lo::server::run() {
  lo::config::require \
    SERVER_CUSTOMER_KEY \
    SERVER_PROVIDER_KEY \
    SERVER_IDENTIFIER \
    SERVER_IP_ADDRESS \
    SERVER_PORT \
    SERVER_QUERY_PORT \
    SERVER_SLOTS \
    INSTALL_DIR

  lo::server::_assert_installed
  lo::config::print

  local bin
  bin=$(lo::server::_binary)
  local -a args=(
    "Mist"
    -log
    -messaging
    -NoLiveServer
    -EnableParallelCharacterMovement
    "-identifier=${SERVER_IDENTIFIER}"
    "-port=${SERVER_PORT}"
    "-QueryPort=${SERVER_QUERY_PORT}"
    "-CustomerKey=${SERVER_CUSTOMER_KEY}"
    "-ProviderKey=${SERVER_PROVIDER_KEY}"
    "-slots=${SERVER_SLOTS}"
    "-OverrideConnectionAddress=${SERVER_IP_ADDRESS}"
  )

  # Append extra UE CLI flags verbatim (word-split intentional)
  if [[ -n "${SERVER_OPTIONS:-}" ]]; then
    # shellcheck disable=SC2206
    args+=(${SERVER_OPTIONS})
  fi

  lo::log::info "starting dedicated server: ${SERVER_IDENTIFIER} on ${SERVER_IP_ADDRESS}:${SERVER_PORT} (query ${SERVER_QUERY_PORT})"
  # exec → become PID 1's child of tini; signals forward cleanly.
  exec "$bin" "${args[@]}"
}
