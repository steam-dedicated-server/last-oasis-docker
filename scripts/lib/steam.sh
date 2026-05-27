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

# Internal: app_update, optionally appending the `validate` token.
#
# IMPORTANT: STEAM_APP_ID (920720) is the installer app that SteamCMD
# actually downloads. STEAM_LINUX_APP_ID (903950) is a separate runtime
# id written into steam_appid.txt after install so MistServer identifies
# itself to Steam's matchmaking backend with the right app. Using
# 903950 for app_update fails with `Invalid platform` because that app
# has no SteamCMD depot.
lo::steam::_app_update() {
  local mode=${1:-}
  local -a extra=()
  if [[ "$mode" == "validate" ]]; then
    extra+=(validate)
  fi

  lo::config::require INSTALL_DIR STEAM_APP_ID STEAM_USER
  install -d -m 0755 "$INSTALL_DIR"

  lo::log::info "steamcmd app_update ${STEAM_APP_ID} (user=${STEAM_USER}) → ${INSTALL_DIR}"
  # Flags:
  #   +@ShutdownOnFailedCommand 1 — exit non-zero on first failed step
  #     (otherwise steamcmd may swallow errors and return 0).
  #   +@NoPromptForPassword 1     — fail fast on bad creds instead of
  #     blocking on an interactive prompt.
  #   +app_license_request        — pre-warm the anonymous license
  #     cache; avoids transient "Missing configuration" on first run.
  lo::retry lo::steam::cmd \
    +@ShutdownOnFailedCommand 1 \
    +@NoPromptForPassword 1 \
    +force_install_dir "$INSTALL_DIR" \
    +login "$STEAM_USER" \
    +app_license_request "$STEAM_APP_ID" \
    +app_update "$STEAM_APP_ID" "${extra[@]}" \
    +quit

  # Write steam_appid.txt inside the game binary dir so MistServer
  # identifies itself with the runtime app id instead of the
  # installer app.
  if [[ -n "${STEAM_LINUX_APP_ID:-}" ]]; then
    local bin_dir="${INSTALL_DIR}/Mist/Binaries/Linux"
    if [[ -d "$bin_dir" ]]; then
      printf '%s\n' "$STEAM_LINUX_APP_ID" > "${bin_dir}/steam_appid.txt"
      lo::log::info "wrote ${bin_dir}/steam_appid.txt = ${STEAM_LINUX_APP_ID}"
    fi
  fi

  lo::log::ok "steamcmd app_update finished"
}

lo::steam::install()  { lo::steam::_app_update validate; }
lo::steam::update()   { lo::steam::_app_update; }
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
