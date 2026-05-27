#!/usr/bin/env bash
# steam.sh — steamcmd wrappers.
# shellcheck shell=bash

[[ -n "${LO_STEAM_LOADED:-}" ]] && return 0
readonly LO_STEAM_LOADED=1

# Resolve steamcmd binary: prefer pre-installed image binary, fall back to PATH.
lo::steam::cmd() {
  local bin="${STEAMCMD_BIN:-/home/steam/steamcmd/steamcmd.sh}"
  if [[ ! -x "$bin" ]]; then
    bin=$(command -v steamcmd || true)
    [[ -z "$bin" ]] && lo::die "steamcmd not found (set STEAMCMD_BIN or install steamcmd)"
  fi
  "$bin" "$@"
}

# Internal: app_update with optional `validate` argument.
lo::steam::_app_update() {
  local validate=$1
  lo::config::require INSTALL_DIR STEAM_LINUX_APP_ID STEAM_USER
  install -d -m 0755 "$INSTALL_DIR"

  lo::log::info "steamcmd app_update ${STEAM_LINUX_APP_ID} (user=${STEAM_USER}) → ${INSTALL_DIR}"
  # NB: +force_install_dir MUST come before +login per steamcmd quirks.
  lo::retry lo::steam::cmd \
    +@sSteamCmdForcePlatformType linux \
    +force_install_dir "$INSTALL_DIR" \
    +login "$STEAM_USER" \
    +app_update "$STEAM_LINUX_APP_ID" $validate \
    +quit
  lo::log::ok "steamcmd app_update finished"
}

lo::steam::install()  { lo::steam::_app_update validate; }
lo::steam::update()   { lo::steam::_app_update ""; }
lo::steam::validate() { lo::steam::_app_update validate; }

lo::steam::login() {
  lo::config::require STEAM_USER
  if [[ "$STEAM_USER" == "anonymous" ]]; then
    lo::log::info "STEAM_USER=anonymous — login not required"
    return 0
  fi
  lo::log::info "interactive steamcmd login as ${STEAM_USER}"
  lo::steam::cmd +login "$STEAM_USER" +quit
}
