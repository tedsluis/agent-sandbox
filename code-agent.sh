#!/usr/bin/env bash
# Start een APARTE VS Code-instantie voor agentwerk, met een schone omgeving:
# geen SSH-agent, geen tokens, geen KUBECONFIG, geen X11 (DISPLAY) voor de container. Je normale VS Code en terminals blijven ongemoeid.
set -euo pipefail

# code-insiders of code; overschrijfbaar: CODE_BIN=code ./code-agent.sh
CODE_BIN="${CODE_BIN:-code-insiders}"
CODE_PATH="$(command -v "$CODE_BIN")"

# Optioneel: code-agent.sh [--force] repo [repo ...] → eerst repo-keuze vastleggen (zie select-repos.sh)
if [ $# -gt 0 ]; then
  "$(cd "$(dirname "$0")" && pwd)/select-repos.sh" "$@"
  echo "Kies na het openen: F1 → Dev Containers: Rebuild and Reopen in Container"
fi

exec env -i \
  HOME="$HOME" USER="$USER" LOGNAME="$USER" LANG="${LANG:-C.UTF-8}" \
  PATH="/usr/local/bin:/usr/bin:/bin" \
  WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}" \
  XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-}" \
  DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-}" \
  XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-}" \
  "$CODE_PATH" --new-window --ozone-platform=wayland \
       --user-data-dir "$HOME/.config/Code-Insiders-agent" \
       --extensions-dir "$HOME/.vscode-insiders-agent/extensions" \
       "$HOME/agent-sandbox"