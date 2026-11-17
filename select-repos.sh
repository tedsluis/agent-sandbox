#!/usr/bin/env bash
# Kies welke repo's uit de bronmap (repo-root.conf, standaard ~/git) in de agent-container gemount worden (B-02).
# Gebruik: select-repos.sh [--force] repo [repo ...]   → keuze vastleggen en lokale config genereren
#          select-repos.sh                            → huidige keuze tonen
#          select-repos.sh --regenerate               → lokale config opnieuw genereren uit sjabloon + repos.conf
#                                                       (code-agent.sh doet dit bij elke start)
# Gegenereerd en niet in git (.gitignore, B-17): .devcontainer/devcontainer.json, .devcontainer/tst.code-workspace, repos.conf.
# Bron in git: .devcontainer/devcontainer.template.jsonc. Na een andere keuze: Rebuild and Reopen in Container.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
CONF="$DIR/repos.conf"; DENY="$DIR/repos.deny"; RROOT="$DIR/repo-root.conf"
TPL="$DIR/.devcontainer/devcontainer.template.jsonc"
DC="$DIR/.devcontainer/devcontainer.json"; WS="$DIR/.devcontainer/tst.code-workspace"
die(){ echo "select-repos: $*" >&2; exit 1; }
force=0; regen=0; args=()
for a in "$@"; do
  case "$a" in --force) force=1 ;; --regenerate) regen=1 ;; *) args+=("$a") ;; esac
done
set -- "${args[@]+"${args[@]}"}"
if [ $# -eq 0 ] && [ $regen = 0 ]; then
  if [ -f "$CONF" ]; then echo "Huidige repo's (repos.conf):"; grep -v '^[[:space:]]*#' "$CONF" | sed 's/^/  /'
  else echo "Nog geen repo's gekozen: select-repos.sh <repo> [<repo> ...]"; fi
  exit 0
fi
[ $regen = 0 ] || [ $# -eq 0 ] || die "--regenerate neemt geen repo-namen"
[ -f "$TPL" ] || die "sjabloon ontbreekt: $TPL"

# Bronmap relatief aan $HOME (B-17); mounts gebruiken ${localEnv:HOME}, dus geen persoonlijke paden in de config
rel=git
[ ! -f "$RROOT" ] || rel=$(grep -v '^[[:space:]]*#' "$RROOT" | tr -d '[:space:]')
rel=${rel:-git}
[[ "$rel" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*(/[A-Za-z0-9][A-Za-z0-9._-]*)*$ ]] \
  || die "repo-root.conf: ongeldig pad '$rel' (relatief aan \$HOME, bijvoorbeeld: git)"
GIT="$HOME/$rel"
{ [ -d "$GIT" ] && [ ! -L "$GIT" ]; } || die "bronmap $GIT bestaat niet of is een symlink (repo-root.conf)"
[ "$(realpath "$GIT")" = "$(realpath "$HOME")/$rel" ] || die "bronmap $GIT wijst buiten \$HOME"

# Basiscontrole per repo (ook bij --regenerate); de scan op secrets alleen bij een nieuwe keuze
check_repo(){ local r=$1 p="$GIT/$1"
  [[ "$r" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "ongeldige naam: '$r'"
  { [ -d "$p" ] && [ ! -L "$p" ]; } || die "$p bestaat niet, is geen map of is een symlink"
  [ "$(realpath "$p")" = "$(realpath "$GIT")/$r" ] || die "$p wijst buiten ~/$rel"
  [ "$(realpath "$p")" != "$(realpath "$DIR")" ] || die "~/agent-sandbox mag niet gemount worden (B-03)"
  [ -e "$p/.git" ] || die "$p is geen git-repo"
  if [ -f "$DENY" ] && grep -v '^[[:space:]]*#' "$DENY" | grep -qxF "$r"; then die "$r staat in repos.deny"; fi
}
# Scan op bestanden met secrets; alleen paden tonen, nooit inhoud
scan_repo(){ local r=$1 p="$GIT/$1" hits
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
}

declare -A seen=(); repos=()
if [ $regen = 1 ]; then
  [ -f "$CONF" ] || die "nog geen repo's gekozen: $DIR/select-repos.sh <repo> [<repo> ...]"
  mapfile -t list < <(grep -v '^[[:space:]]*#' "$CONF" | sed '/^[[:space:]]*$/d')
  [ ${#list[@]} -gt 0 ] || die "repos.conf is leeg: kies repo's met select-repos.sh <repo>"
else
  list=("$@")
fi
for r in "${list[@]}"; do
  [ -z "${seen[$r]:-}" ] || continue; seen[$r]=1
  check_repo "$r"; [ $regen = 1 ] || scan_repo "$r"
  repos+=("$r")
done

mnt(){ printf 'source=${localEnv:HOME}/%s/%s,target=/workspaces/%s,type=bind,z' "$rel" "$1" "$1"; }
gen_block(){ # repos...
  local all="$*" first=$1; shift; local rest=("$@") wf=/workspaces i sep
  [ ${#rest[@]} -gt 0 ] || wf="/workspaces/$first"
  echo '  // BEGIN repos (gegenereerd door select-repos.sh uit repos.conf)'
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
{ grep -q '// BEGIN repos' "$TPL" && grep -q '// END repos' "$TPL" && grep -q '@@GENERATED-NOTICE@@' "$TPL"; } \
  || die "sjabloon mist // BEGIN repos, // END repos of @@GENERATED-NOTICE@@: $TPL"
tdc=$(mktemp "$DIR/.devcontainer/.devcontainer.json.XXXXXX"); tws=$(mktemp "$DIR/.devcontainer/.tst.code-workspace.XXXXXX")
tconf=$(mktemp "$DIR/.repos.conf.XXXXXX")
trap 'rm -f "$tdc" "$tws" "$tconf"' EXIT
B="$(gen_block "${repos[@]}")" awk '
  /@@GENERATED-NOTICE@@/ { print "  // GEGENEREERD uit devcontainer.template.jsonc door select-repos.sh – niet aanpassen; wijzig het sjabloon."; next }
  /\/\/ BEGIN repos/ { print ENVIRON["B"]; skip=1; next }
  /\/\/ END repos/ { skip=0; next }
  !skip' "$TPL" > "$tdc"
gen_ws "${repos[@]}" > "$tws"
for f in "$tdc" "$tws"; do
  python3 -c 'import json,re,sys; json.loads(re.sub(r"(?m)^\s*//.*$","",open(sys.argv[1]).read()))' "$f" || die "gegenereerde JSON ongeldig: $f"
done
{ echo "# Gegenereerd door select-repos.sh (niet in git). Bron: ~/$rel/<naam> -> /workspaces/<naam>"; printf '%s\n' "${repos[@]}"; } > "$tconf"
changed=0
for pair in "$tdc:$DC" "$tws:$WS"; do
  src=${pair%%:*}; dst=${pair#*:}
  if ! cmp -s "$src" "$dst"; then { [ -f "$dst" ] && diff -u "$dst" "$src"; } || true; mv "$src" "$dst"; chmod 644 "$dst"; changed=1; fi
done
# repos.conf alleen herschrijven bij een nieuwe keuze (bij --regenerate blijft de inhoud gelijk)
[ $regen = 1 ] || { mv "$tconf" "$CONF"; chmod 644 "$CONF"; }
if [ $regen = 1 ]; then
  [ $changed = 0 ] || echo "select-repos: lokale config opnieuw gegenereerd uit sjabloon + repos.conf (${repos[*]}); Rebuild nodig"
else
  echo "select-repos: gekozen: ${repos[*]}"
  echo "Volgende stap: ~/agent-sandbox/code-agent.sh en dan F1 → Dev Containers: Rebuild and Reopen in Container"
fi
