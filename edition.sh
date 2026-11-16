# Gedeeld door code-agent.sh en setup-agent-profile.sh (source, niet uitvoeren). Verwacht $DIR.
# Editie: vlag --stable/--insiders > edition.conf > stable.
# Zet: EDITION, CODE_BIN, CODE_PATH, PROFILE_DIR, EXT_DIR, PROXY_ENV, ARGS (overige argumenten) en render_settings.
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
# Proxy (B-15): alleen deze variabelen gaan door env -i, en alleen als ze gezet zijn (zonder proxy: leeg). Nooit credentials.
PROXY_ENV=()
for v in http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY; do
  val=$(printenv "$v" || true); [ -n "$val" ] || continue
  case "$val" in *@*) echo "agent-sandbox: $v bevat credentials (@); niet ondersteund" >&2; exit 1 ;; esac
  PROXY_ENV+=("$v=$val")
done
# Paden (B-17): settings.host.json bevat ${HOME}; Dev Containers vult dat in dockerPath niet zelf in.
[ "$(realpath "$DIR")" = "$(realpath "$HOME/agent-sandbox" 2>/dev/null)" ] \
  || { echo "agent-sandbox: deze map moet ~/agent-sandbox zijn (nu: $DIR)" >&2; exit 1; }
case "$HOME" in *'&'*|*'\'*|*'|'*|*'"'*) echo "agent-sandbox: HOME bevat &, \\, | of \"; niet ondersteund" >&2; exit 1 ;; esac
# GNU sed laat een ontbrekend regeleinde aan het eind intact, zodat de byte-vergelijking (B-14) klopt.
render_settings(){ sed "s|\${HOME}|$HOME|g" "$DIR/settings.host.json"; }
