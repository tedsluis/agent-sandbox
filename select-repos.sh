#!/usr/bin/env bash
# Kies welke repo's uit de bronmap (repo-root.conf, standaard ~/git) in de agent-container gemount worden (B-02).
# Gebruik: select-repos.sh [--force] repo [repo ...]   → keuze vastleggen en config genereren
#          select-repos.sh                            → huidige keuze tonen
#          select-repos.sh --stage-example            → neutrale voorbeeldwaarden in de git-index zetten
#                                                       (vóór een commit; werkkopie blijft ongemoeid, B-17)
# Daarna altijd: Rebuild and Reopen in Container (mounts liggen vast bij aanmaken container).
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
CONF="$DIR/repos.conf"; DENY="$DIR/repos.deny"; RROOT="$DIR/repo-root.conf"
DC="$DIR/.devcontainer/devcontainer.json"; WS="$DIR/.devcontainer/tst.code-workspace"
die(){ echo "select-repos: $*" >&2; exit 1; }
force=0; example=0; args=()
for a in "$@"; do
  case "$a" in --force) force=1 ;; --stage-example) example=1 ;; *) args+=("$a") ;; esac
done
set -- "${args[@]+"${args[@]}"}"
if [ $# -eq 0 ] && [ $example = 0 ]; then
  echo "Huidige repo's (repos.conf):"; grep -v '^[[:space:]]*#' "$CONF" 2>/dev/null | sed 's/^/  /'; exit 0
fi

# Bronmap relatief aan $HOME (B-17); mounts gebruiken ${localEnv:HOME}, dus geen persoonlijke paden in devcontainer.json
rel=git
[ ! -f "$RROOT" ] || rel=$(grep -v '^[[:space:]]*#' "$RROOT" | tr -d '[:space:]')
rel=${rel:-git}
[[ "$rel" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*(/[A-Za-z0-9][A-Za-z0-9._-]*)*$ ]] \
  || die "repo-root.conf: ongeldig pad '$rel' (relatief aan \$HOME, bijvoorbeeld: git)"

mnt(){ printf 'source=${localEnv:HOME}/%s/%s,target=/workspaces/%s,type=bind,z' "$rel" "$1" "$1"; }
gen_block(){ # repos...
  local all="$*" first=$1; shift; local rest=("$@") wf=/workspaces i sep
  [ ${#rest[@]} -gt 0 ] || wf="/workspaces/$first"
  echo '  // BEGIN repos (gegenereerd door select-repos.sh – niet met de hand aanpassen)'
  printf '  "workspaceMount": "%s",\n' "$(mnt "$first")"
  if [ ${#rest[@]} -eq 0 ]; then echo '  "mounts": [],'; else
    echo '  "mounts": ['
    for i in "${!rest[@]}"; do sep=,; [ "$i" -eq $(( ${#rest[@]} - 1 )) ] && sep=; printf '    "%s"%s\n' "$(mnt "${rest[$i]}")" "$sep"; done
    echo '  ],'
  fi
  printf '  "workspaceFolder": "%s",\n' "$wf"
  printf '  "containerEnv": { "AGENT_REPOS": "%s" },\n' "$all"
  echo '  // END repos'
}
gen_ws(){ # repos...
  local all=("$@") i sep
  echo '{'; echo '  "folders": ['
  for i in "${!all[@]}"; do sep=,; [ "$i" -eq $(( ${#all[@]} - 1 )) ] && sep=; printf '    { "path": "/workspaces/%s" }%s\n' "${all[$i]}" "$sep"; done
  echo '  ],'; echo '  "settings": { "chat.useAgentsMdFile": true }'; echo '}'
}
tdc=$(mktemp "$DIR/.devcontainer/.devcontainer.json.XXXXXX"); tws=$(mktemp "$DIR/.devcontainer/.tst.code-workspace.XXXXXX")
tconf=$(mktemp "$DIR/.repos.conf.XXXXXX")
trap 'rm -f "$tdc" "$tws" "$tconf"' EXIT
# Genereert devcontainer.json en workspace in $tdc en $tws en controleert de JSON
render(){ # repos...
  { grep -q '// BEGIN repos' "$DC" && grep -q '// END repos' "$DC"; } || die "markeringen // BEGIN repos en // END repos ontbreken in $DC"
  B="$(gen_block "$@")" awk '/\/\/ BEGIN repos/{print ENVIRON["B"]; skip=1; next} /\/\/ END repos/{skip=0; next} !skip' "$DC" > "$tdc"
  gen_ws "$@" > "$tws"
  local f
  for f in "$tdc" "$tws"; do
    python3 -c 'import json,re,sys; json.loads(re.sub(r"(?m)^\s*//.*$","",open(sys.argv[1]).read()))' "$f" || die "gegenereerde JSON ongeldig: $f"
  done
}

if [ $example = 1 ]; then
  [ $# -eq 0 ] || die "--stage-example neemt geen repo-namen"
  git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "$DIR is geen git-werkkopie"
  rel=git; render voorbeeld-repo
  { echo "# Voorbeeld; wordt overschreven door select-repos.sh. Bron: ~/git/<naam> -> /workspaces/<naam>"; echo voorbeeld-repo; } > "$tconf"
  for pair in "$tdc:.devcontainer/devcontainer.json" "$tws:.devcontainer/tst.code-workspace" "$tconf:repos.conf"; do
    blob=$(git -C "$DIR" hash-object -w "${pair%%:*}")
    git -C "$DIR" update-index --add --cacheinfo "100644,$blob,${pair#*:}"
  done
  git -C "$DIR" --no-pager diff --cached --stat -- .devcontainer/devcontainer.json .devcontainer/tst.code-workspace repos.conf
  echo "select-repos: voorbeeldwaarden staan in de git-index; je werkkopie is ongewijzigd."
  echo "Commit nu; daarna toont git status je eigen repo-keuze als lokaal gewijzigd."
  exit 0
fi

GIT="$HOME/$rel"
{ [ -d "$GIT" ] && [ ! -L "$GIT" ]; } || die "bronmap $GIT bestaat niet of is een symlink (repo-root.conf)"
[ "$(realpath "$GIT")" = "$(realpath "$HOME")/$rel" ] || die "bronmap $GIT wijst buiten \$HOME"

declare -A seen=(); repos=()
for r in "$@"; do
  [[ "$r" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "ongeldige naam: '$r'"
  [ -z "${seen[$r]:-}" ] || continue; seen[$r]=1
  p="$GIT/$r"
  { [ -d "$p" ] && [ ! -L "$p" ]; } || die "$p bestaat niet, is geen map of is een symlink"
  [ "$(realpath "$p")" = "$(realpath "$GIT")/$r" ] || die "$p wijst buiten ~/$rel"
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

render "${repos[@]}"
diff -u "$DC" "$tdc" || true; diff -u "$WS" "$tws" || true
mv "$tdc" "$DC"; mv "$tws" "$WS"; chmod 644 "$DC" "$WS"
{ echo "# Gegenereerd door select-repos.sh op $(date -Iseconds). Bron: ~/$rel/<naam> -> /workspaces/<naam>"; printf '%s\n' "${repos[@]}"; } > "$CONF"
echo "select-repos: gekozen: ${repos[*]}"
echo "Volgende stap: ~/agent-sandbox/code-agent.sh en dan F1 → Dev Containers: Rebuild and Reopen in Container"
