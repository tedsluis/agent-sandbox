#!/usr/bin/env bash
# initializeCommand: draait op de host met de omgeving van de VS Code-instantie.
set -u
diag(){
  echo "agent-sandbox: DISPLAY='${DISPLAY:-}' VSCODE_CLI='${VSCODE_CLI:-}' ouder: $(ps -o args= -p "$PPID" | cut -c1-120)" >&2
  echo "agent-sandbox: variabelen (alleen namen): $(env | cut -d= -f1 | sort | tr '\n' ' ')" >&2
}
fail(){ echo "agent-sandbox: $1 – start via ~/agent-sandbox/code-agent.sh" >&2; diag; exit 1; }
[ -z "${SSH_AUTH_SOCK:-}" ] || fail "SSH_AUTH_SOCK is gezet"
# Echte X-displays hebben een ':' (":0", "host:1"). VS Code zet zelf DISPLAY=1 als dummy voor SSH_ASKPASS.
case "${DISPLAY:-}" in *:*) fail "DISPLAY is gezet (X11)";; esac
[ -z "${KUBECONFIG:-}" ]    || fail "KUBECONFIG is gezet"
bad=$(env | cut -d= -f1 | grep -iE 'token|vault|passw|secret' | tr '\n' ' ')
[ -z "$bad" ] || fail "secret-achtige variabelen in omgeving: $bad"
exit 0
