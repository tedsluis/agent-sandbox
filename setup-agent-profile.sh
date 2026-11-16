#!/usr/bin/env bash
# Agentprofiel voor een VS Code-editie inrichten: eenmalig, en na elke wijziging van settings.host.json.
# Gebruik: setup-agent-profile.sh [--stable|--insiders]
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/edition.sh"
[ ${#ARGS[@]} -eq 0 ] || { echo "setup-agent-profile: onbekende argumenten: ${ARGS[*]}" >&2; exit 1; }
mkdir -p "$PROFILE_DIR/User" "$EXT_DIR"
S="$PROFILE_DIR/User/settings.json"
if [ -f "$S" ] && ! cmp -s "$DIR/settings.host.json" "$S"; then
  cp -p "$S" "$S.bak-$(date +%Y%m%d%H%M%S)"; echo "oude settings.json bewaard als $S.bak-…"
fi
cp "$DIR/settings.host.json" "$S"
code_agent(){ env -i HOME="$HOME" PATH=/usr/local/bin:/usr/bin:/bin "$CODE_PATH" --user-data-dir "$PROFILE_DIR" --extensions-dir "$EXT_DIR" "$@"; }
code_agent --install-extension ms-vscode-remote.remote-containers
code_agent --list-extensions --show-versions
cmp "$DIR/settings.host.json" "$S" && echo "OK: $EDITION-profiel ingericht ($PROFILE_DIR)"
