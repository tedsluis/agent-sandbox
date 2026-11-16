#!/usr/bin/env bash
# Kies welke repo's uit ~/git in de agent-container gemount worden (B-02).
# Gebruik: select-repos.sh [--force] repo [repo ...]   → keuze vastleggen en config genereren
#          select-repos.sh                            → huidige keuze tonen
# Daarna altijd: Rebuild and Reopen in Container (mounts liggen vast bij aanmaken container).
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
GIT="$HOME/git"
CONF="$DIR/repos.conf"; DENY="$DIR/repos.deny"
DC="$DIR/.devcontainer/devcontainer.json"; WS="$DIR/.devcontainer/tst.code-workspace"
die(){ echo "select-repos: $*" >&2; exit 1; }
force=0; args=()
for a in "$@"; do if [ "$a" = --force ]; then force=1; else args+=("$a"); fi; done
set -- "${args[@]+"${args[@]}"}"
if [ $# -eq 0 ]; then
  echo "Huidige repo's (repos.conf):"; grep -v '^[[:space:]]*#' "$CONF" 2>/dev/null | sed 's/^/  /'; exit 0
fi

declare -A seen=(); repos=()
for r in "$@"; do
  [[ "$r" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "ongeldige naam: '$r'"
  [ -z "${seen[$r]:-}" ] || continue; seen[$r]=1
  p="$GIT/$r"
  { [ -d "$p" ] && [ ! -L "$p" ]; } || die "$p bestaat niet, is geen map of is een symlink"
  [ "$(realpath "$p")" = "$(realpath "$GIT")/$r" ] || die "$p wijst buiten ~/git"
  [ "$(realpath "$p")" != "$(realpath "$DIR")" ] || die "~/agent-sandbox mag niet gemount worden (B-03)"
  [ -e "$p/.git" ] || die "$p is geen git-repo"
  if [ -f "$DENY" ] && grep -v '^[[:space:]]*#' "$DENY" | grep -qxF "$r"; then die "$r staat in repos.deny"; fi
  # Scan op bestanden met secrets; alleen paden tonen, nooit inhoud
  hits=$(find "$p" -path "$p/.git" -prune -o \( -iname '*kubeconfig*' -o -name '.env' -o -name '*.pem' \
        -o -name 'id_rsa*' -o -name 'id_ed25519*' -o -name 'id_ecdsa*' -o -name '.vault_pass*' \
        -o -name '*.kdbx' -o -name '.git-credentials' \) -print 2>/dev/null | head -20)
  if [ -f "$p/.git/config" ] && grep -qE '://[^/@:]+:[^/@]+@' "$p/.git/config"; then
    hits="$hits"$'\n'"$p/.git/config (credentials in remote-URL)"
  fi
  if [ -n "${hits//[[:space:]]/}" ]; then
    echo "select-repos: gevoelige bestanden in $r:" >&2; sed '/^$/d; s/^/  /' <<<"$hits" >&2
    [ $force = 1 ] || die "afgebroken; gebruik --force als je dit bewust accepteert"
  fi
  repos+=("$r")
done

grep -q '// BEGIN repos' "$DC" && grep -q '// END repos' "$DC" || die "markeringen // BEGIN repos en // END repos ontbreken in $DC"
mnt(){ printf 'source=${localEnv:HOME}/git/%s,target=/workspaces/%s,type=bind,z' "$1" "$1"; }
first=${repos[0]}; rest=("${repos[@]:1}")
if [ ${#repos[@]} -eq 1 ]; then wf="/workspaces/$first"; else wf=/workspaces; fi
block=$(
  echo '  // BEGIN repos (gegenereerd door select-repos.sh – niet met de hand aanpassen)'
  printf '  "workspaceMount": "%s",\n' "$(mnt "$first")"
  if [ ${#rest[@]} -eq 0 ]; then echo '  "mounts": [],'; else
    echo '  "mounts": ['
    for i in "${!rest[@]}"; do sep=,; [ "$i" -eq $(( ${#rest[@]} - 1 )) ] && sep=; printf '    "%s"%s\n' "$(mnt "${rest[$i]}")" "$sep"; done
    echo '  ],'
  fi
  printf '  "workspaceFolder": "%s",\n' "$wf"
  printf '  "containerEnv": { "AGENT_REPOS": "%s" },\n' "${repos[*]}"
  echo '  // END repos'
)

tdc=$(mktemp "$DIR/.devcontainer/.devcontainer.json.XXXXXX"); tws=$(mktemp "$DIR/.devcontainer/.tst.code-workspace.XXXXXX")
trap 'rm -f "$tdc" "$tws"' EXIT
B="$block" awk '/\/\/ BEGIN repos/{print ENVIRON["B"]; skip=1; next} /\/\/ END repos/{skip=0; next} !skip' "$DC" > "$tdc"
{
  echo '{'; echo '  "folders": ['
  for i in "${!repos[@]}"; do sep=,; [ "$i" -eq $(( ${#repos[@]} - 1 )) ] && sep=; printf '    { "path": "/workspaces/%s" }%s\n' "${repos[$i]}" "$sep"; done
  echo '  ],'; echo '  "settings": { "chat.useAgentsMdFile": true }'; echo '}'
} > "$tws"
for f in "$tdc" "$tws"; do
  python3 -c 'import json,re,sys; json.loads(re.sub(r"(?m)^\s*//.*$","",open(sys.argv[1]).read()))' "$f" || die "gegenereerde JSON ongeldig: $f"
done
diff -u "$DC" "$tdc" || true; diff -u "$WS" "$tws" || true
mv "$tdc" "$DC"; mv "$tws" "$WS"; chmod 644 "$DC" "$WS"
{ echo "# Gegenereerd door select-repos.sh op $(date -Iseconds). Bron: ~/git/<naam> -> /workspaces/<naam>"; printf '%s\n' "${repos[@]}"; } > "$CONF"
echo "select-repos: gekozen: ${repos[*]}"
echo "Volgende stap: ~/agent-sandbox/code-agent.sh en dan F1 → Dev Containers: Rebuild and Reopen in Container"
