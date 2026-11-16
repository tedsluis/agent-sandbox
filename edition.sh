# Gedeeld door code-agent.sh en setup-agent-profile.sh (source, niet uitvoeren). Verwacht $DIR.
# Editie: vlag --stable/--insiders > edition.conf > stable.
# Zet: EDITION, CODE_BIN, CODE_PATH, PROFILE_DIR, EXT_DIR en ARGS (overige argumenten).
EDITION=""; ARGS=()
for a in "$@"; do
  case "$a" in --stable) EDITION=stable ;; --insiders) EDITION=insiders ;; *) ARGS+=("$a") ;; esac
done
if [ -z "$EDITION" ] && [ -f "$DIR/edition.conf" ]; then
  EDITION=$(grep -v '^[[:space:]]*#' "$DIR/edition.conf" | tr -d '[:space:]')
fi
EDITION=${EDITION:-stable}
case "$EDITION" in
  stable)   CODE_BIN=code;          PROFILE_DIR="$HOME/.config/Code-agent";          EXT_DIR="$HOME/.vscode-agent/extensions" ;;
  insiders) CODE_BIN=code-insiders; PROFILE_DIR="$HOME/.config/Code-Insiders-agent"; EXT_DIR="$HOME/.vscode-insiders-agent/extensions" ;;
  *) echo "agent-sandbox: onbekende editie '$EDITION' (stable|insiders)" >&2; exit 1 ;;
esac
CODE_PATH="$(command -v "$CODE_BIN")" || { echo "agent-sandbox: $CODE_BIN niet gevonden; installeer VS Code $EDITION" >&2; exit 1; }
