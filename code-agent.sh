#!/usr/bin/env bash
# Start een APARTE VS Code-instantie (stable of Insiders) voor agentwerk, met een schone omgeving:
# geen SSH-agent, geen tokens, geen KUBECONFIG, geen X11 (DISPLAY). Alleen proxyvariabelen (zie edition.sh)
# en AGENT_UID/AGENT_GID (host-UID/GID voor de image-build, B-17) gaan mee.
# Je normale VS Code en terminals blijven ongemoeid.
# Gebruik: code-agent.sh [--stable|--insiders] [--force] [repo ...]   (editie standaard uit edition.conf)
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/edition.sh"

# Niet starten met een profiel dat afwijkt van settings.host.json (bijv. zonder podman-wrapper of met Wayland-socket)
if ! cmp -s <(render_settings) "$PROFILE_DIR/User/settings.json"; then
  echo "agent-sandbox: profiel $PROFILE_DIR wijkt af van settings.host.json – draai: $DIR/setup-agent-profile.sh --$EDITION" >&2; exit 1
fi
if ! ls -d "$EXT_DIR"/ms-vscode-remote.remote-containers-* >/dev/null 2>&1; then
  echo "agent-sandbox: Dev Containers ontbreekt in $EXT_DIR – draai: $DIR/setup-agent-profile.sh --$EDITION" >&2; exit 1
fi
[ "$(id -u)" != 0 ] || { echo "agent-sandbox: niet als root starten" >&2; exit 1; }

if [ ${#ARGS[@]} -gt 0 ]; then
  "$DIR/select-repos.sh" "${ARGS[@]}"
  echo "Kies na het openen: F1 → Dev Containers: Rebuild and Reopen in Container"
fi
echo "agent-sandbox: start VS Code $EDITION ($CODE_BIN)"
exec env -i \
  HOME="$HOME" USER="$USER" LOGNAME="$USER" LANG="${LANG:-C.UTF-8}" \
  AGENT_UID="$(id -u)" AGENT_GID="$(id -g)" \
  PATH="/usr/local/bin:/usr/bin:/bin" \
  WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}" \
  XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-}" \
  DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-}" \
  XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-}" \
  "${PROXY_ENV[@]}" \
  "$CODE_PATH" --new-window --ozone-platform=wayland \
       --user-data-dir "$PROFILE_DIR" \
       --extensions-dir "$EXT_DIR" \
       "$DIR"
