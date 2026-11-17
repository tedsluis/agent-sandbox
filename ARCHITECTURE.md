# ARCHITECTURE – agent-sandbox

## 1. Overzicht

```text
Fedora 45 host (gewone gebruiker, UID n ≠ 0)
│
├── Gewone sessie (ongewijzigd)
│   ├── GNOME Terminal: tokens in env, ssh-agent, ~/.kube, sudo
│   └── eigen VS Code (stable/Insiders) voor normaal werk
│
└── code-agent.sh  ──►  aparte VS Code-instantie (stable of Insiders, edition.conf)
        env -i (geen SSH_AUTH_SOCK, tokens, KUBECONFIG, DISPLAY)
        --user-data-dir ~/.config/Code-agent | ~/.config/Code-Insiders-agent
        --extensions-dir ~/.vscode-agent/extensions | ~/.vscode-insiders-agent/extensions
        --ozone-platform=wayland
        weigert start als profiel ≠ settings.host.json
        opent ~/agent-sandbox  ──►  Dev Containers-extensie
                                       │ initializeCommand: guard-host-env.sh
                                       │ podman-agent.sh → podman (rootless, SELinux aan)
                                       ▼
        ┌─────────────── container "agent-sandbox" ──────────────────┐
        │ user agent (UID = host-UID, keep-id), cap-drop=ALL,        │
        │ no-new-privileges, container_t, geen sudo/ssh/curl/oc/...  │
        │ VS Code Server (stable/Insiders) + Copilot Chat (ext host) │
        │ tools: git-core, kustomize, yamllint, grep, find, diff, jq │
        │ /workspaces/<repo>  ◄── bind mounts ,z (repos.conf)        │
        │ /opt/tst.code-workspace (multi-root), check-isolation      │
        └────────────────────────────────────────────────────────────┘
```

UI draait op de host; alles wat code uitvoert of bestanden leest (VS Code Server, extensies, terminals, agent-tools) draait in de container.

## 2. Bestanden

| Bestand (in `~/agent-sandbox/`) | Functie |
|---|---|
| `.devcontainer/Containerfile` | Multi-stage image. Stage `tools` (`fedora:45`): kustomize downloaden en tegen `checksums.txt` controleren. Eindstage (`fedora-minimal:45`): `git-core grep findutils diffutils jq yamllint tar gzip shadow-utils openssl3-libs ca-certificates` (`openssl3-libs`: Copilot-runtime vraagt `libssl.so.3`, Fedora 45 heeft standaard OpenSSL 4); `openssh-clients`, `curl`, `curl-minimal`, `wget` met `rpm -e --nodeps` verwijderd en **build faalt** als een verboden tool nog vindbaar is (als afhankelijkheid komen wel `python3` (van `yamllint`) en `openssh` zonder client mee); gebruiker `agent` met de UID/GID van de host (build-args `USER_UID`/`USER_GID` uit `AGENT_UID`/`AGENT_GID`, standaard 1000; B-17); `/workspaces` en `extensionsCache` voor `.vscode-server` en `.vscode-server-insiders`; workspacebestand naar `/opt`, `check-isolation` naar `/usr/local/bin`. |
| `.devcontainer/devcontainer.json` | Repo-blok (gegenereerd), runArgs, remoteEnv, `initializeCommand`, extensies (alleen `redhat.vscode-yaml`; Copilot Chat is ingebouwd), container-settings. |
| `.devcontainer/tst.code-workspace` | Multi-root workspace met de repo's uit `repos.conf` (gegenereerd door `select-repos.sh`); `chat.useAgentsMdFile: true`. Wordt in de image gekopieerd. |
| `README.md` | Gebruikershandleiding: repo's kiezen, image bouwen, Dev Container gebruiken, controleren. |
| `code-agent.sh` | Start de aparte VS Code-instantie met schone omgeving. Editie via `--stable`/`--insiders` of `edition.conf` (standaard stable). Weigert te starten als het profiel afwijkt van `settings.host.json` of Dev Containers ontbreekt. |
| `edition.sh`, `edition.conf` | Bepaalt editie, programma, profiel- en extensiemap; standaard-editie. Weigert als de map niet `~/agent-sandbox` is; `render_settings` vult `${HOME}` in `settings.host.json` in (B-17). Zet ook `PROXY_ENV`: de proxyvariabelen die door `env -i` mogen (B-15), weigert proxy-URL's met credentials. |
| `setup-agent-profile.sh` | Richt het agentprofiel per editie in: schrijft `settings.host.json` met ingevuld `${HOME}` (`render_settings`), installeert Dev Containers. |
| `podman-agent.sh` | `dev.containers.dockerPath`-wrapper: verwijdert `--security-opt label=disable` (door devcontainers CLI ≥ 0.80 altijd toegevoegd) bij `podman run/create`. |
| `guard-host-env.sh` | `initializeCommand` op de host: breekt af als `AGENT_UID`/`AGENT_GID` ontbreken of afwijken van `id -u`/`id -g` (B-17), of als `SSH_AUTH_SOCK`, een X11-`DISPLAY` (met `:`; VS Code zet zelf dummy `DISPLAY=1`), `KUBECONFIG` of secret-achtige variabelen in de omgeving van VS Code staan. |
| `select-repos.sh` | Kiest de repo's uit de bronmap (validatie + scan op secrets), genereert repo-blok in `devcontainer.json` en `tst.code-workspace`, schrijft `repos.conf`. `--stage-example` zet neutrale voorbeeldwaarden (`voorbeeld-repo`) in de git-index zonder de werkkopie te wijzigen (B-17). |
| `repo-root.conf` | Optioneel: bronmap van de repo's, relatief aan `$HOME` (standaard `git`). Niet `$HOME` zelf, geen `..` of absolute paden. |
| `repos.conf` | Huidige repo-keuze (gegenereerd). |
| `repos.deny` | Repo's die `select-repos.sh` altijd weigert (nu leeg). |
| `settings.host.json` | Sjabloon (met `${HOME}`) voor `User/settings.json` van het agentprofiel (stable: `~/.config/Code-agent`, Insiders: `~/.config/Code-Insiders-agent`); gekopieerd door `setup-agent-profile.sh`. |
| `.devcontainer/check-isolation.sh` | Controle binnen de container; in de image als `/usr/local/bin/check-isolation` (root-eigendom). Niveaus OK/WARN/FOUT; exitcode 1 bij FOUT. Controleert o.a. dat de agent-UID niet 0 is en eigenaar is van elke gemounte repo, en dat de bron van elke `/workspaces/<repo>`-mount de repo-map zelf is. `REPOS` (standaard `AGENT_REPOS` uit `containerEnv`) en optioneel `CHECK_INTERNAL="host:poort …"`. |
| `.claude/settings.json` | Rechten en sandbox voor Claude Code op de host bij werk aan deze repo (deny-regels volgen AGENTS.md). |
| `.githooks/pre-commit` | Weigert commits met een eigen repo-keuze (`repos.conf`, repo-blok, `tst.code-workspace` anders dan `voorbeeld-repo`), `repo-root.conf` of het eigen home-pad. Activeren: `git config core.hooksPath .githooks` (B-17). |
| `.gitignore` | Houdt `repo-root.conf`, tijdelijke bestanden van `select-repos.sh` en `*.bak-*` buiten git. |

## 3. Isolatielagen

| Laag | Mechanisme | Waar ingesteld |
|---|---|---|
| Proces/namespaces | Rootless podman, user namespace `keep-id` (gezet door devcontainers CLI omdat `remoteUser` niet root is; host-UID = agent-UID via build-args, B-17) | devcontainers CLI |
| Rechten | `--cap-drop=ALL`, `--security-opt=no-new-privileges`, `--pids-limit=1024`, geen sudo | `runArgs`, `Containerfile` |
| Bestandssysteem | Alleen de repo's uit `repos.conf` gemount (gekozen en gescand door `select-repos.sh`); config buiten mounts; geen `$HOME`, `.kube`, `.ssh`, podman-socket | `workspaceMount`, `mounts` |
| SELinux | `container_file_t` via `,z`; container draait als `container_t` doordat `podman-agent.sh` `label=disable` verwijdert | `workspaceMount`, `podman-agent.sh`, `settings.host.json` |
| Startcontrole | `code-agent.sh` start niet buiten `~/agent-sandbox`, als root, als het agentprofiel afwijkt van `settings.host.json` (na invullen van `${HOME}`) of Dev Containers ontbreekt; `initializeCommand` weigert start/koppeling vanuit een VS Code-instantie met `SSH_AUTH_SOCK`, X11-`DISPLAY` (met `:`), `KUBECONFIG` of secret-achtige variabelen | `code-agent.sh`, `guard-host-env.sh`, `devcontainer.json` |
| Omgeving | `env -i` bij start, alleen proxyvariabelen (`http(s)_proxy`, `no_proxy`, ook hoofdletters) gaan mee als ze gezet zijn, zonder credentials (B-15; podman geeft ze door aan pull, build en container), plus `AGENT_UID`/`AGENT_GID` voor de image-build (B-17); `remoteEnv` zet `SSH_AUTH_SOCK`, `DISPLAY`, `WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`, `BROWSER` leeg (`BROWSER` wordt in de VS Code-terminal toch door de server gezet, backlog 19), `KUBECONFIG=/dev/null`, `GIT_TERMINAL_PROMPT=0`; `terminal.integrated.inheritEnv: false` | `code-agent.sh`, `setup-agent-profile.sh`, `edition.sh`, `guard-host-env.sh`, `devcontainer.json` |
| Credentials | Geen gitconfig-kopie, git credential helper `none`, docker credential helper uit, geen agent forwarding; `git.terminalAuthentication` en `github.gitAuthentication` uit | `settings.host.json`, `devcontainer.json` |
| Tools | Alleen benodigde tools; geen ssh, oc, kubectl, helm, ansible, vault, kubeseal, curl, wget; build faalt als er een vindbaar is | `Containerfile` |
| Grafisch | Native Wayland zonder `DISPLAY` (geen X11-forwarding); Wayland-socket niet gemount | `code-agent.sh`, `settings.host.json` |
| Gedeelde staat | Geen `vscode`-cachevolume | `settings.host.json` |
| Extensieplaatsing | `remote.extensionKind` dwingt Copilot naar `workspace` (container). Copilot Chat is ingebouwd en wordt niet van de Marketplace geïnstalleerd. Let op: in het lokale venster vóór "Reopen in Container" draait Copilot op de host (backlog 21) | `settings.host.json`, `devcontainer.json` |
| Agentgedrag | Auto-approve alleen voor `kustomize build`, `yamllint`, lezende tools, `git status/diff/log` (niet verder aangescherpt, B-16) | `devcontainer.json` → `chat.tools.terminal.autoApprove` |

## 4. Mounts

| Host | Container | Optie |
|---|---|---|
| `~/<bronmap>/<eerste repo>` (standaard `~/git`, `repo-root.conf`) | `/workspaces/<eerste repo>` | `type=bind,z` (workspaceMount) |
| `~/<bronmap>/<overige repo's>` | `/workspaces/<repo>` | `type=bind,z` (mounts) |

Repo's wisselen gaat met `select-repos.sh`; het genereert het blok tussen `// BEGIN repos` en `// END repos` in `devcontainer.json` (eerste repo = `workspaceMount`, overige in `mounts`, `containerEnv.AGENT_REPOS`) en `tst.code-workspace`, en legt de keuze vast in `repos.conf`. Nooit `~/git` als geheel (B-02).

```bash
~/agent-sandbox/select-repos.sh repo-a repo-b   # keuze vastleggen (of: code-agent.sh repo-a repo-b)
~/agent-sandbox/select-repos.sh                      # huidige keuze tonen
# daarna: F1 → Dev Containers: Rebuild and Reopen in Container
```

`select-repos.sh` weigert: ongeldige namen (`/`, `..`), symlinks of paden buiten de bronmap, een ongeldige `repo-root.conf` (niet relatief aan `$HOME`, `..`), `~/agent-sandbox`, mappen zonder `.git`, namen uit `repos.deny`, en repo's met gevoelige bestanden (`*kubeconfig*`, `.env`, `*.pem`, `id_*`, `.vault_pass*`, `*.kdbx`, `.git-credentials`, credentials in remote-URL) tenzij `--force`.

Na openen, bij meerdere repo's: **File → Open Workspace from File… → `/opt/tst.code-workspace`**, zodat Copilot per repo de `AGENTS.md` vindt. Huidige keuze: `select-repos.sh` zonder argumenten.

## 5. Host-instellingen agentprofiel (`settings.host.json`)

| Instelling | Waarde | Doel |
|---|---|---|
| `dev.containers.dockerPath` | `${HOME}/agent-sandbox/podman-agent.sh` (ingevuld door `setup-agent-profile.sh`; Dev Containers vult `${HOME}`/`~` hier niet zelf in, B-17) | podman i.p.v. docker, via wrapper die `label=disable` verwijdert |
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
| Agent leest tokens uit env | Afgedekt (getest 2026-11-15: guard-diagnose, `check-isolation`) | `env -i`, `guard-host-env.sh`, geen `.bashrc`-tokens in container |
| Agent gebruikt ssh-agent | Afgedekt (getest 2026-11-15: geen socket, geen ssh) | geen `SSH_AUTH_SOCK` op host-instantie (guard); geen ssh-client. Audit 2026-11-15 vond `vscode-ssh-auth`-socket in oude container |
| Agent gebruikt `.kube`-tokens | Afgedekt (getest 2026-11-15: mounts) | niet gemount (ook geen kubeconfig via `~/git`), geen oc/kubectl, `KUBECONFIG=/dev/null` |
| Agent pusht met jouw git-hosting-rechten | Afgedekt (getest 2026-11-15: geen helper, `GIT_ASKPASS` leeg) | geen credential helper, geen gitconfig-kopie, geen askpass (`git.terminalAuthentication: false`); restkanaal `REMOTE_CONTAINERS_IPC` nog toetsen (backlog 19) |
| Agent wordt root op host | Afgedekt | rootless, geen sudo, cap-drop (`CapEff=0`), no-new-privileges (gemeten 2026-11-15) |
| Container draait zonder SELinux-scheiding | Afgedekt (getest 2026-11-15: `container_t`) | `podman-agent.sh` verwijdert `label=disable` |
| Container geopend vanuit gewone of verouderde VS Code (met env, ssh-agent, DISPLAY, oude instellingen) | Afgedekt (guard blokkeerde in de praktijk; test vanuit gewone VS Code nog open) | `initializeCommand` → `guard-host-env.sh`; profielcontrole in `code-agent.sh` |
| Agent past eigen containerconfig aan | Afgedekt | config buiten mounts |
| Agent start nieuwe container met meer rechten | Afgedekt | geen podman-socket |
| Toetsaanslagen via X11/Wayland | Afgedekt (getest 2026-11-15/16: geen sockets of mount; log: `X11 forwarding: DISPLAY not set on local host`) | geen X11-`DISPLAY` (guard blokkeert waarden met `:`), native Wayland, `mountWaylandSocket: false`, `remoteEnv` leeg |
| Andere dev containers beïnvloeden via cachevolume | Afgedekt (getest 2026-11-15: niet gemount) | `cacheVolume: false`; volume `vscode` blijft voor andere dev containers |
| Agent leest andere repo's in `~/git` | Afgedekt (getest 2026-11-15 met twee verschillende keuzes) | alleen repo's uit `repos.conf` gemount; `check-isolation` vergelijkt met `AGENT_REPOS` |
| Gekozen repo bevat secrets (kubeconfig, `.env`, keys) | Beperkt | `select-repos.sh` scant en weigert, tenzij bewust `--force` |
| Verboden tool zit (via basisimage) toch in de image | Afgedekt (curl gevonden en verwijderd 2026-11-15) | `rpm -e` + build-check in Containerfile; `check-isolation` |
| Kanalen naar host-UI (`BROWSER`, `VSCODE_IPC_HOOK_CLI`, `REMOTE_CONTAINERS_IPC`, `VSCODE_GIT_IPC_HANDLE`, MCP-socket) | **Open** (WARN in `check-isolation`) | backlog 19 |
| Copilot draait op de host in het lokale agent-venster (vóór Reopen in Container) | **Open** | alleen chatten ná Reopen in Container; backlog 21. Ná Reopen draait de agent host in de container (bevestigd 2026-11-16: `[AgentHost:remote]`, `--type=agentHost` in container) |
| Agent bereikt interne netwerken/clusters | **Geaccepteerd** (B-16) | geen credentials in de container; domeinen uit `no_proxy` gaan direct; host-poorten 22 (sshd) en 8080 bereikbaar via `host.containers.internal` (gemeten 2026-11-16) |
| Exfiltratie van repo-inhoud via internet | **Geaccepteerd** (B-16) | Copilot heeft internet nodig. Achter een http-proxy loopt egress via die proxy (`check-isolation`: `WARN egress via proxy`), ook als direct internet dicht is |
| Agent opent eigen netwerkverbindingen met `python3` (afhankelijkheid van `yamllint`), ondanks ontbreken van curl/wget/ssh | **Geaccepteerd** (B-16) | geen credentials; zelfde restrisico als hierboven |
| Proxy-credentials lekken naar de container | Afgedekt (B-15; Insiders getest 2026-11-16, stable te toetsen in backlog 22) | alleen proxy-URL's zonder `@`: `edition.sh` weigert, `guard-host-env.sh` blokkeert, `check-isolation` geeft FOUT |
| Agent wijzigt of verwijdert bestanden in de gekozen repo's | Geaccepteerd | git als vangnet; review vóór commit |
| Agent maakt lokale commits | Geaccepteerd (te herzien) | geen push mogelijk; backlog 10 |
| Kwaadaardige inhoud in repo (prompt injection via AGENTS.md e.d.) | Beperkt | impact begrensd door bovenstaande lagen |

## 7. Bekende versies (per werkplek)

| Component | Werkplek zonder proxy (2026-11-16) | Werkplek met proxy (tests 2026-11-16) |
|---|---|---|
| Fedora / kernel | 45 / 7.3.3-300.fc45 | 45 / 7.2.15-300.fc45 |
| VS Code stable | 1.146.0 (commit 69047191), Copilot Chat 0.74.0 ingebouwd (end-to-end nog toetsen, backlog 22) | niet vastgelegd |
| VS Code Insiders | 1.147.0-insider (commit d8e7b56c), Copilot Chat 0.75.2026111203 ingebouwd | 1.146.0-insider (commit 6605820e), Copilot Chat ingebouwd |

| Component | Versie |
|---|---|
| podman / buildah | 6.1.4 / 1.45.2 |
| Dev Containers-extensie | 0.474.0 (devcontainers CLI 0.90.0) |
| Base images | `registry.fedoraproject.org/fedora:45`, `fedora-minimal:45` |
| kustomize | 5.7.1 |
| git-core / yamllint / jq / openssl3-libs | 2.56.1 / 1.38.0 / 1.8.2 / 3.5.9 |

## 8. Werkwijze dagelijks

0. Eenmalig per editie (en na wijziging van `settings.host.json`): `~/agent-sandbox/setup-agent-profile.sh --stable` / `--insiders`.
1. `~/agent-sandbox/code-agent.sh` (andere repo's: `code-agent.sh <repo> [<repo> …]`; andere editie: `--stable`/`--insiders`)
2. **Reopen in Container** (na wijziging Containerfile/devcontainer.json of andere repo-keuze: **Rebuild and Reopen**).
3. Bij meerdere repo's: open `/opt/tst.code-workspace`.
4. Agent werkt en valideert in de container. Chat pas ná Reopen in Container (backlog 21).
5. Review, commit en push in een eigen terminal op de host.

## 9. Verificatie

- Build los: `podman build -t agent-sandbox-test ~/agent-sandbox/.devcontainer`
- Run los (image met standaard-UID 1000; keep-id koppelt jouw UID daaraan): `podman run --rm -it --userns=keep-id:uid=1000,gid=1000 --cap-drop=ALL --security-opt=no-new-privileges --mount type=bind,source=$HOME/git/<repo>,target=/workspaces/<repo>,z agent-sandbox-test bash -c 'id; ls /workspaces/<repo> | head; kustomize version'`
- Profiel: `code-agent.sh` start alleen als `settings.host.json` gelijk is aan het profiel; anders melding `profiel … wijkt af`.
- Dev Containers-log (Output → Dev Containers) mag **niet** bevatten: `X11 forwarding: DISPLAY in container`, `wayland-0`, `source=vscode`, `Exit code 1` aan het eind. Moet wel bevatten: `--docker-path <HOME>/agent-sandbox/podman-agent.sh` en `--build-arg USER_UID=<jouw UID>`. Let op: het `podman run`-commando in de log bevat wél `--security-opt label=disable`, omdat de CLI dat toevoegt vóór `podman-agent.sh` het weghaalt; controleer SELinux daarom met `podman inspect` (`ProcessLabel` = `container_t`, `SecurityOpt` zonder `label=disable`).
- Het terminalpaneel toont na het openen het logtabblad "Dev Containers" (geen prompt, elke minuut `Extensions cache, remote removals: None`). Open een shell met `+` / Ctrl+Shift+`.
- In container (VS Code-terminal, niet `podman exec`): `check-isolation` — geen `FOUT`; `WARN` alleen voor bekende restrisico's (host-UI-kanalen, netwerk). Interne doelen meetesten: `CHECK_INTERNAL="api.cluster.example:6443" check-isolation`.