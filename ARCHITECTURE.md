# ARCHITECTURE – agent-sandbox

## 1. Overzicht

```text
Fedora 45 host (gebruiker tedsluis, UID 1000)
│
├── Gewone sessie (ongewijzigd)
│   ├── GNOME Terminal: tokens in env, ssh-agent, ~/.kube, sudo
│   └── eigen VS Code (Insiders/stable) voor normaal werk
│
└── code-agent.sh  ──►  aparte VS Code Insiders-instantie
        env -i (geen SSH_AUTH_SOCK, tokens, KUBECONFIG, DISPLAY)
        --user-data-dir ~/.config/Code-Insiders-agent
        --extensions-dir ~/.vscode-insiders-agent/extensions
        --ozone-platform=wayland
        opent ~/agent-sandbox  ──►  Dev Containers-extensie
                                       │ podman (rootless)
                                       ▼
        ┌─────────────── container "agent-sandbox" ───────────────┐
        │ user agent (UID 1000 via keep-id), cap-drop=ALL,          │
        │ no-new-privileges, geen sudo/ssh/oc/kubectl/helm/curl     │
        │ VS Code Server Insiders + Copilot Chat (extension host)   │
        │ tools: git-core, kustomize, yamllint, grep, find, diff, jq│
        │ /workspaces/genai-proxy  ◄── bind mount ,z (repolijst PROJECT.md) │
        │ /opt/tst.code-workspace (multi-root)                   │
        └───────────────────────────────────────────────────────────┘
```

UI draait op de host; alles wat code uitvoert of bestanden leest (VS Code Server, extensies, terminals, agent-tools) draait in de container.

## 2. Bestanden

| Bestand (in `~/agent-sandbox/`) | Functie |
|---|---|
| `.devcontainer/Containerfile` | Multi-stage image. Stage `tools` (`fedora:45`): kustomize downloaden en tegen `checksums.txt` controleren. Eindstage (`fedora-minimal:45`): `git-core grep findutils diffutils jq yamllint tar gzip shadow-utils`; `openssh-clients` (meegetrokken door git) met `rpm -e --nodeps` verwijderd; gebruiker `agent` (UID/GID 1000); `/workspaces` en `extensionsCache`-mappen aangemaakt; workspacebestand naar `/opt`. |
| `.devcontainer/devcontainer.json` | Mounts, runArgs, remoteEnv, `initializeCommand`, extensies, container-settings. |
| `.devcontainer/tst.code-workspace` | Multi-root workspace met de repo's uit `repos.conf` (nu `genai-proxy`; gegenereerd door `select-repos.sh`); `chat.useAgentsMdFile: true`. Wordt in de image gekopieerd. |
| `README.md` | Gebruikershandleiding: repo's kiezen, image bouwen, Dev Container gebruiken, controleren. |
| `code-agent.sh` | Start de aparte VS Code-instantie met schone omgeving. `CODE_BIN` standaard `code-insiders`. |
| `podman-agent.sh` | `dev.containers.dockerPath`-wrapper: verwijdert `--security-opt label=disable` (door devcontainers CLI ≥ 0.80 altijd toegevoegd) bij `podman run/create`. |
| `guard-host-env.sh` | `initializeCommand` op de host: breekt af als `SSH_AUTH_SOCK`, een X11-`DISPLAY` (met `:`; VS Code zet zelf dummy `DISPLAY=1`), `KUBECONFIG` of secret-achtige variabelen in de omgeving van VS Code staan. |
| `select-repos.sh` | Kiest de repo's (validatie + scan op secrets), genereert repo-blok in `devcontainer.json` en `tst.code-workspace`, schrijft `repos.conf`. |
| `repos.conf` | Huidige repo-keuze (gegenereerd). |
| `repos.deny` | Repo's die `select-repos.sh` altijd weigert (nu leeg). |
| `settings.host.json` | Bron voor `~/.config/Code-Insiders-agent/User/settings.json` (host-side instellingen van het agentprofiel). |
| `.devcontainer/check-isolation.sh` | Controle binnen de container; in de image als `/usr/local/bin/check-isolation` (root-eigendom). Niveaus OK/WARN/FOUT; exitcode 1 bij FOUT. `REPOS` (standaard `AGENT_REPOS` uit `containerEnv`) en optioneel `CHECK_INTERNAL="host:poort …"`. |
| `.claude/settings.json` | Rechten en sandbox voor Claude Code op de host bij werk aan deze repo. |

## 3. Isolatielagen

| Laag | Mechanisme | Waar ingesteld |
|---|---|---|
| Proces/namespaces | Rootless podman, user namespace `keep-id` (gezet door devcontainers CLI omdat `remoteUser` niet root is; host-UID 1000 = `agent`) | devcontainers CLI |
| Rechten | `--cap-drop=ALL`, `--security-opt=no-new-privileges`, `--pids-limit=1024`, geen sudo | `runArgs`, `Containerfile` |
| Bestandssysteem | Alleen de repo's uit `repos.conf` gemount (gekozen en gescand door `select-repos.sh`); config buiten mounts; geen `$HOME`, `.kube`, `.ssh`, podman-socket | `workspaceMount`, `mounts` |
| SELinux | `container_file_t` via `,z`; container draait als `container_t` doordat `podman-agent.sh` `label=disable` verwijdert | `workspaceMount`, `podman-agent.sh`, `settings.host.json` |
| Startcontrole | `initializeCommand` weigert start/koppeling vanuit een VS Code-instantie met `SSH_AUTH_SOCK`, X11-`DISPLAY` (met `:`), `KUBECONFIG` of secret-achtige variabelen | `guard-host-env.sh`, `devcontainer.json` |
| Omgeving | `env -i` bij start; `remoteEnv` zet `SSH_AUTH_SOCK`, `DISPLAY`, `WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`, `BROWSER` leeg, `KUBECONFIG=/dev/null`, `GIT_TERMINAL_PROMPT=0`; `terminal.integrated.inheritEnv: false` | `code-agent.sh`, `devcontainer.json` |
| Credentials | Geen gitconfig-kopie, git credential helper `none`, docker credential helper uit, geen agent forwarding; `git.terminalAuthentication` en `github.gitAuthentication` uit | `settings.host.json`, `devcontainer.json` |
| Tools | Alleen benodigde tools; geen ssh, oc, kubectl, helm, ansible, vault, kubeseal, curl | `Containerfile` |
| Grafisch | Native Wayland zonder `DISPLAY` (geen X11-forwarding); Wayland-socket niet gemount | `code-agent.sh`, `settings.host.json` |
| Gedeelde staat | Geen `vscode`-cachevolume | `settings.host.json` |
| Extensieplaatsing | `remote.extensionKind` dwingt Copilot naar `workspace` (container) | `settings.host.json` |
| Agentgedrag | Auto-approve alleen voor `kustomize build`, `yamllint`, lezende tools, `git status/diff/log` | `devcontainer.json` → `chat.tools.terminal.autoApprove` |

## 4. Mounts

| Host | Container | Optie |
|---|---|---|
| `~/git/genai-proxy` | `/workspaces/genai-proxy` | `type=bind,z` (workspaceMount) |

Repo's wisselen gaat met `select-repos.sh`; het genereert het blok tussen `// BEGIN repos` en `// END repos` in `devcontainer.json` (eerste repo = `workspaceMount`, overige in `mounts`, `containerEnv.AGENT_REPOS`) en `tst.code-workspace`, en legt de keuze vast in `repos.conf`. Nooit `~/git` als geheel (B-02).

```bash
~/agent-sandbox/select-repos.sh genai-proxy argocd   # keuze vastleggen (of: code-agent.sh genai-proxy argocd)
~/agent-sandbox/select-repos.sh                      # huidige keuze tonen
# daarna: F1 → Dev Containers: Rebuild and Reopen in Container
```

`select-repos.sh` weigert: ongeldige namen (`/`, `..`), symlinks of paden buiten `~/git`, `~/agent-sandbox`, mappen zonder `.git`, namen uit `repos.deny`, en repo's met gevoelige bestanden (`*kubeconfig*`, `.env`, `*.pem`, `id_*`, `.vault_pass*`, `*.kdbx`, `.git-credentials`, credentials in remote-URL) tenzij `--force`.

Na openen: **File → Open Workspace from File… → `/opt/tst.code-workspace`**, zodat Copilot per repo de `AGENTS.md` vindt.

## 5. Host-instellingen agentprofiel (`settings.host.json`)

| Instelling | Waarde | Doel |
|---|---|---|
| `dev.containers.dockerPath` | `/home/tedsluis/agent-sandbox/podman-agent.sh` | podman i.p.v. docker, via wrapper die `label=disable` verwijdert |
| `dev.containers.copyGitConfig` | `false` | geen `.gitconfig` (credential helpers, aliassen) naar container |
| `dev.containers.gitCredentialHelperConfigLocation` | `none` | geen git credential helper die naar host terugroept |
| `dev.containers.dockerCredentialHelper` | `false` | geen registry-credentials |
| `remote.SSH.enableAgentForwarding` | `false` | geen ssh-agent via Remote-SSH |
| `dev.containers.cacheVolume` | `false` | geen gedeeld `vscode`-volume (naam bevestigd in 0.472.0/0.474.0) |
| `dev.containers.mountWaylandSocket` | `false` | geen Wayland-socket in container (naam bevestigd in 0.472.0/0.474.0) |
| `remote.extensionKind` | Copilot → `workspace` | Copilot draait in container |

## 6. Dreigingsmodel

| Dreiging | Status | Maatregel |
|---|---|---|
| Agent leest tokens uit env | Afgedekt (te testen) | `env -i`, `guard-host-env.sh`, geen `.bashrc`-tokens in container |
| Agent gebruikt ssh-agent | Afgedekt (te testen) | geen `SSH_AUTH_SOCK` op host-instantie (guard); geen ssh-client. Audit 2026-11-15 vond `vscode-ssh-auth`-socket in oude container |
| Agent gebruikt `.kube`-tokens | Afgedekt (te testen) | niet gemount (ook geen kubeconfig via `~/git`), geen oc/kubectl, `KUBECONFIG=/dev/null` |
| Agent pusht met jouw Bitbucket-rechten | Afgedekt (te testen) | geen credential helper, geen gitconfig-kopie, geen askpass (`git.terminalAuthentication: false`) |
| Agent wordt root op host | Afgedekt | rootless, geen sudo, cap-drop (`CapEff=0`), no-new-privileges (gemeten 2026-11-15) |
| Container draait zonder SELinux-scheiding | Afgedekt (getest 2026-11-15: `container_t`) | `podman-agent.sh` verwijdert `label=disable`; verwacht `container_t` |
| Container geopend vanuit gewone VS Code (met env, ssh-agent, DISPLAY) | Afgedekt (te testen) | `initializeCommand` → `guard-host-env.sh` |
| Agent past eigen containerconfig aan | Afgedekt | config buiten mounts |
| Agent start nieuwe container met meer rechten | Afgedekt | geen podman-socket |
| Toetsaanslagen via X11/Wayland | Afgedekt (getest 2026-11-15: geen sockets/mount; log nog nalopen) | geen X11-`DISPLAY` (guard blokkeert waarden met `:`), native Wayland, `mountWaylandSocket: false`, `remoteEnv` leeg |
| Andere dev containers beïnvloeden via cachevolume | Afgedekt (getest 2026-11-15: niet gemount) | `cacheVolume: false`; volume `vscode` blijft voor andere dev containers |
| Agent leest andere repo's in `~/git` | Afgedekt (getest 2026-11-15: alleen `genai-proxy`) | alleen `genai-proxy` gemount |
| Kanalen naar host-UI (`BROWSER`, `VSCODE_IPC_HOOK_CLI`, `REMOTE_CONTAINERS_IPC`, MCP-socket) | Te onderzoeken | `BROWSER` leeg; rest backlog 19 |
| Agent bereikt interne netwerken/clusters | **Open** | geen credentials, maar netwerk vrij; zie backlog 4 |
| Exfiltratie van repo-inhoud via internet | **Open** | Copilot heeft internet nodig; allowlist-proxy (backlog 4) |
| Agent wijzigt of verwijdert bestanden in de zes repo's | Geaccepteerd | git als vangnet; review vóór commit |
| Agent maakt lokale commits | Geaccepteerd (te herzien) | geen push mogelijk; backlog 10 |
| Kwaadaardige inhoud in repo (prompt injection via AGENTS.md e.d.) | Beperkt | impact begrensd door bovenstaande lagen |

## 7. Bekende versies (laatste test)

| Component | Versie |
|---|---|
| Fedora (host) | 45 (kernel in log: 7.3.3-300.fc45) |
| podman / buildah | 6.1.4 / 1.45.2 |
| VS Code Insiders | 1.147.0-insider (commit d8e7b56c) |
| Dev Containers-extensie | 0.474.0 (devcontainers CLI 0.90.0) |
| Base images | `registry.fedoraproject.org/fedora:45`, `fedora-minimal:45` |
| kustomize | 5.7.1 |
| git-core / yamllint / jq | 2.56.0 / 1.38.0 / 1.8.1 |

## 8. Werkwijze dagelijks

1. `~/agent-sandbox/code-agent.sh` (andere repo's: `code-agent.sh <repo> [<repo> …]`)
2. **Reopen in Container** (na wijziging Containerfile/devcontainer.json of andere repo-keuze: **Rebuild and Reopen**).
3. Open `/opt/tst.code-workspace`.
4. Agent werkt en valideert in de container.
5. Review, commit en push in een eigen terminal op de host.

## 9. Verificatie

- Build los: `podman build -t agent-sandbox-test ~/agent-sandbox/.devcontainer`
- Run los: `podman run --rm -it --userns=keep-id:uid=1000,gid=1000 --cap-drop=ALL --security-opt=no-new-privileges --mount type=bind,source=$HOME/git/argocd,target=/workspaces/argocd,z agent-sandbox-test bash -c 'id; ls /workspaces/argocd | head; kustomize version'`
- Dev Containers-log (Output → Dev Containers) mag **niet** bevatten: `X11 forwarding`, `wayland-0`, `source=vscode`, `label=disable` in het `podman run`-commando, `Exit code 1` aan het eind. Moet wel bevatten: `--docker-path /home/tedsluis/agent-sandbox/podman-agent.sh`.
- In container (VS Code-terminal, niet `podman exec`): `check-isolation` — geen `FOUT`; `WARN` alleen voor bekende restrisico's (host-UI-kanalen, netwerk). Interne doelen meetesten: `CHECK_INTERNAL="api.cluster.example:6443" check-isolation`.