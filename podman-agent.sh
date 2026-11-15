#!/usr/bin/env bash
# dockerPath voor het agentprofiel. De devcontainers CLI (>= 0.80) zet bij podman altijd
# '--security-opt label=disable'; dit haalt dat weg bij run/create zodat de container als container_t draait.
set -euo pipefail
PODMAN=/usr/bin/podman
sub=""
for a in "$@"; do case "$a" in -*) ;; *) sub="$a"; break ;; esac; done
[[ "$sub" == run || "$sub" == create ]] || exec "$PODMAN" "$@"
out=()
while (($#)); do
  if [[ "$1" == --security-opt && "${2:-}" == label=disable ]]; then shift 2; continue; fi
  if [[ "$1" == --security-opt=label=disable ]]; then shift; continue; fi
  out+=("$1"); shift
done
exec "$PODMAN" "${out[@]}"
