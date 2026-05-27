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

# UE4 dedicated servers built with the Steam SDK dlopen steamclient.so
# from $HOME/.steam/sdk{32,64}/. steamcmd drops the runtime under
# different paths depending on version, so search known locations and
# symlink the first hit.
lo::server::_link_steamclient() {
  local arch link target candidate
  for arch in 32 64; do
    link="$HOME/.steam/sdk${arch}/steamclient.so"
    [[ -e "$link" ]] && continue

    target=""
    for candidate in \
      "$HOME/.steam/steamcmd/linux${arch}/steamclient.so" \
      "$HOME/Steam/steamcmd/linux${arch}/steamclient.so" \
      "$HOME/.steam/steam/linux${arch}/steamclient.so" \
      "$HOME/.steam/Steam/linux${arch}/steamclient.so" \
      "/home/steam/steamcmd/linux${arch}/steamclient.so"; do
      if [[ -e "$candidate" ]]; then
        target="$candidate"
        break
      fi
    done

    if [[ -z "$target" ]]; then
      lo::log::warn "steamclient.so for linux${arch} not found in any expected path"
      continue
    fi

    mkdir -p "$(dirname "$link")"
    ln -sfT "$target" "$link"
    lo::log::info "linked $link → $target"
  done
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
  lo::server::_link_steamclient

  # Help libraries that dlopen by name (not absolute path) find
  # steamclient.so.
  export LD_LIBRARY_PATH="$HOME/.steam/sdk64:$HOME/.steam/sdk32${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

  # Headroom for FDs (Steam SDK + many concurrent player connections).
  ulimit -n 65536 2>/dev/null || true

  local bin
  bin=$(lo::server::_binary)

  # Built-in flags:
  #   -log                              — write Mist.log
  #   -force_steamclient_link           — UE4 uses Steam SDK linkage
  #   -messaging                        — engine messaging subsystem
  #   -NoLiveServer                     — disable live-server gating
  #   -USEALLAVAILABLECORES             — UE4 task graph across cores
  #   -EnableParallelCharacterMovement  — parallel character movement
  #   -backendapiurloverride=…          — production matchmaking backend
  local -a args=(
    -log
    -force_steamclient_link
    -messaging
    -NoLiveServer
    -EnableParallelCharacterMovement
    -USEALLAVAILABLECORES
    -backendapiurloverride=backend.last-oasis.com
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
