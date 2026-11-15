#!/usr/bin/env bash
# Draai in de VS Code-terminal BINNEN de dev container: `check-isolation`
# (niet via podman exec: dan ontbreekt de VS Code-omgeving).
# OK = in orde, WARN = bekend restrisico (PROJECT.md), FOUT = isolatie gebroken. Exitcode 1 bij een FOUT.
REPOS="${REPOS:-${AGENT_REPOS:-}}"
fail=0; warn=0
ok(){ echo "OK   $*"; }; bad(){ echo "FOUT $*"; fail=1; }; wrn(){ echo "WARN $*"; warn=1; }

# --- Omgeving
n=$(env | cut -d= -f1 | grep -iE 'token|vault|passw|secret|openssl' | tr '\n' ' ')
[ -z "$n" ] && ok "geen secret-achtige variabelen" || bad "secret-achtige variabelen: $n"
[ -z "${SSH_AUTH_SOCK:-}" ] && ok "SSH_AUTH_SOCK leeg" || bad "SSH_AUTH_SOCK gezet"
[ -z "${DISPLAY:-}" ] && ok "DISPLAY leeg" || bad "DISPLAY gezet"
[ -z "${WAYLAND_DISPLAY:-}" ] && ok "WAYLAND_DISPLAY leeg" || bad "WAYLAND_DISPLAY gezet"
[ -z "${GIT_ASKPASS:-}" ] && ok "GIT_ASKPASS leeg" || bad "GIT_ASKPASS gezet"
[ "${KUBECONFIG:-}" = /dev/null ] && ok "KUBECONFIG=/dev/null" || bad "KUBECONFIG='${KUBECONFIG:-}'"

# --- Sockets en grafische sessie
s=$(ls -d /tmp/.X11-unix /tmp/vscode-ssh-auth-* /tmp/vscode-wayland-* /run/user/*/wayland-* /run/user/*/bus 2>/dev/null | tr '\n' ' ')
[ -z "$s" ] && ok "geen X11/Wayland/ssh-agent/DBus-sockets" || bad "sockets: $s"
s=$(ls -d /run/podman/podman.sock /var/run/docker.sock /run/docker.sock /run/user/*/podman/podman.sock 2>/dev/null | tr '\n' ' ')
[ -z "$s" ] && ok "geen container-socket" || bad "container-socket: $s"

# --- Mounts
mps=$(awk '{print $5}' /proc/self/mountinfo)
[ -n "$REPOS" ] || bad "AGENT_REPOS leeg: repo-keuze onbekend"
for r in $REPOS; do grep -qx "/workspaces/$r" <<<"$mps" && ok "mount /workspaces/$r" || bad "mount /workspaces/$r ontbreekt"; done
extra=$(grep '^/workspaces' <<<"$mps" | grep -vxF -f <(printf '/workspaces/%s\n' $REPOS) | tr '\n' ' ')
[ -z "$extra" ] && ok "geen andere mounts onder /workspaces" || bad "onverwachte mounts: $extra"
grep -qx /vscode <<<"$mps" && bad "vscode-cachevolume gemount" || ok "geen vscode-cachevolume"
src=$(awk '{print $4}' /proc/self/mountinfo | grep -E '/\.(ssh|kube|gnupg|config|local)(/|$)|^/home[0-9]*/[^/]+/?$|/git/?$' | tr '\n' ' ')
[ -z "$src" ] && ok "geen \$HOME, ~/git of dotdirs van host gemount" || bad "gevoelige bron gemount: $src"

# --- Rechten en SELinux
grep -qE '^CapEff:\s*0+$' /proc/self/status && ok "geen capabilities" || bad "capabilities aanwezig"
grep -qE '^NoNewPrivs:\s*1' /proc/self/status && ok "no-new-privileges" || bad "no-new-privileges uit"
grep -qE '^Seccomp:\s*2' /proc/self/status && ok "seccomp actief" || bad "seccomp uit"
grep -q ':container_t:' /proc/self/attr/current 2>/dev/null && ok "SELinux container_t" || bad "SELinux-label: $(cat /proc/self/attr/current 2>/dev/null)"
[ "$(id -u)" = 1000 ] && ok "uid 1000" || bad "uid $(id -u)"

# --- Tools en credentials
found=""
for t in ssh scp sftp sudo su curl wget oc kubectl helm ansible ansible-playbook vault kubeseal podman docker; do
  command -v "$t" >/dev/null && found="$found $t"; done
[ -z "$found" ] && ok "geen verboden tools" || bad "verboden tools:$found"
found=""
for f in "$HOME/.kube" "$HOME/.ssh" "$HOME/.gnupg" "$HOME/.git-credentials" "$HOME/.docker/config.json"; do
  [ -e "$f" ] && found="$found $f"; done
[ -z "$found" ] && ok "geen credential-bestanden in \$HOME" || bad "credential-bestanden:$found"
git config --global --get-all credential.helper >/dev/null 2>&1 && bad "git credential helper (global)" || ok "geen git credential helper (global)"
git config --system --get-all credential.helper >/dev/null 2>&1 && bad "git credential helper (system)" || ok "geen git credential helper (system)"

# --- Schrijfbaarheid buiten /workspaces en $HOME
found=""
for d in / /etc /usr /usr/local/bin /opt /var /run; do [ -w "$d" ] && found="$found $d"; done
[ -z "$found" ] && ok "systeempaden niet schrijfbaar" || bad "schrijfbaar:$found"

# --- Kanalen naar host-UI (bekend restrisico, backlog 19)
[ -n "${BROWSER:-}" ] && wrn "BROWSER gezet (URL's openen in host-browser)"
[ -n "${VSCODE_IPC_HOOK_CLI:-}" ] && wrn "VSCODE_IPC_HOOK_CLI (code-CLI naar host-UI)"
[ -n "${REMOTE_CONTAINERS_IPC:-}" ] && wrn "REMOTE_CONTAINERS_IPC (Dev Containers-IPC naar host)"
ls -d /tmp/mcp-* >/dev/null 2>&1 && wrn "MCP-socket(s) in /tmp"

# --- Netwerk (bekend open, backlog 4)
for p in 22 80 443 631 5432 6443 8080 9090; do
  timeout 2 bash -c "</dev/tcp/host.containers.internal/$p" 2>/dev/null && wrn "host.containers.internal:$p bereikbaar"; done
timeout 3 bash -c '</dev/tcp/1.1.1.1/443' 2>/dev/null && wrn "internet bereikbaar (egress open)"
for hp in ${CHECK_INTERNAL:-}; do
  timeout 3 bash -c "</dev/tcp/${hp%:*}/${hp##*:}" 2>/dev/null && bad "intern doel $hp bereikbaar" || ok "intern doel $hp niet bereikbaar"; done

echo "---"
if [ $fail = 0 ]; then
  [ $warn = 1 ] && echo "RESULTAAT: geen FOUT, wel WARN (bekende restrisico's)" || echo "RESULTAAT: alles OK"
else
  echo "RESULTAAT: FOUT gevonden"
fi
exit $fail
