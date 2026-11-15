# agent-sandbox

Een afgeschermde VS Code Dev Container waarin AI-agents (GitHub Copilot) in een paar gekozen git-repo's kunnen werken, **zonder** toegang tot je tokens, ssh-agent, `~/.kube`, sudo of je andere repo's.

- Waarom en welke besluiten: [PROJECT.md](PROJECT.md)
- Hoe het werkt en het dreigingsmodel: [ARCHITECTURE.md](ARCHITECTURE.md)

## In het kort

```bash
~/agent-sandbox/code-agent.sh genai-proxy        # repo kiezen en aparte VS Code starten
# in VS Code: F1 → Dev Containers: Rebuild and Reopen in Container
# in de container-terminal:
check-isolation                                  # moet eindigen met "geen FOUT"
```

## 1. Eenmalig instellen

De sandbox gebruikt een **aparte** VS Code Insiders-instantie met een eigen profiel (`~/.config/Code-Insiders-agent`) en eigen extensies (`~/.vscode-insiders-agent/extensions`). Je gewone VS Code blijft ongemoeid.

1. Installeer de Dev Containers-extensie in het agentprofiel:

   ```bash
   code-insiders --user-data-dir ~/.config/Code-Insiders-agent \
                 --extensions-dir ~/.vscode-insiders-agent/extensions \
                 --install-extension ms-vscode-remote.remote-containers
   ```

2. Zet de host-instellingen van het agentprofiel (podman-wrapper, geen credential-forwarding, geen Wayland-socket, geen gedeeld cachevolume):

   ```bash
   mkdir -p ~/.config/Code-Insiders-agent/User
   cp ~/agent-sandbox/settings.host.json ~/.config/Code-Insiders-agent/User/settings.json
   ```

   Herhaal deze `cp` telkens als `settings.host.json` verandert. Controleren:
   `diff ~/agent-sandbox/settings.host.json ~/.config/Code-Insiders-agent/User/settings.json`

   > `settings.host.json` bevat het pad `/home/tedsluis/agent-sandbox/podman-agent.sh`. Gebruik je een andere home directory, pas dat pad dan aan.

## 2. Git-repo's kiezen

De container ziet **alleen** de repo's die je kiest; elke repo uit `~/git/<repo>` verschijnt als `/workspaces/<repo>`. Nooit heel `~/git`.

```bash
~/agent-sandbox/select-repos.sh genai-proxy             # één repo
~/agent-sandbox/select-repos.sh genai-proxy argocd      # meerdere repo's
~/agent-sandbox/select-repos.sh                         # huidige keuze tonen
```

Of in één keer met starten: `~/agent-sandbox/code-agent.sh genai-proxy argocd`.

`select-repos.sh` past `.devcontainer/devcontainer.json` en `.devcontainer/tst.code-workspace` aan, schrijft de keuze naar `repos.conf` en toont de wijziging. Pas het blok tussen `// BEGIN repos` en `// END repos` niet met de hand aan.

Het script **weigert** een repo als:

- de naam ongeldig is (bijvoorbeeld `../x`) of de map niet bestaat;
- het een symlink is of buiten `~/git` wijst;
- het geen git-repo is (geen `.git`);
- de naam in `repos.deny` staat;
- er bestanden in staan die op secrets lijken (`*kubeconfig*`, `.env`, `*.pem`, ssh-keys, `.vault_pass*`, `*.kdbx`, `.git-credentials`, of credentials in een remote-URL).

In het laatste geval zie je welke bestanden het zijn. Haal ze weg, of ga bewust door met `--force`:

```bash
~/agent-sandbox/select-repos.sh --force <repo>
```

> Na elke andere repo-keuze is **Rebuild and Reopen in Container** nodig: mounts liggen vast zodra de container is aangemaakt.

## 3. De container-image bouwen

Normaal bouwt VS Code de image voor je bij **Rebuild and Reopen in Container** (zie stap 4). De image staat in `.devcontainer/Containerfile`:

- basis `fedora-minimal:45`;
- tools: `git-core`, `kustomize` (checksum gecontroleerd), `yamllint`, `jq`, `grep`, `find`, `diff`;
- **niet** aanwezig: `ssh`, `curl`, `sudo`, `oc`, `kubectl`, `helm`, `ansible`;
- gebruiker `agent` (UID 1000), plus `/usr/local/bin/check-isolation`.

Los bouwen om een fout in de Containerfile te zien:

```bash
podman build -t agent-sandbox-test ~/agent-sandbox/.devcontainer
```

Opnieuw bouwen is nodig na een wijziging in `.devcontainer/` (Containerfile, `devcontainer.json`, repo-keuze).

## 4. De Dev Container gebruiken in VS Code

1. **Start altijd via het script**, nooit vanuit je gewone VS Code:

   ```bash
   ~/agent-sandbox/code-agent.sh
   ```

   Het script start VS Code met een lege omgeving (`env -i`): geen tokens, geen ssh-agent, geen `KUBECONFIG`. Open je de map toch vanuit je gewone VS Code, dan weigert de container te starten met `agent-sandbox: … – start via ~/agent-sandbox/code-agent.sh`.

2. Kies **F1 → Dev Containers: Reopen in Container**.
   Na een wijziging (Containerfile, repo-keuze, `devcontainer.json`): **F1 → Dev Containers: Rebuild and Reopen in Container**.

3. Bij meerdere repo's: **File → Open Workspace from File… → `/opt/tst.code-workspace`**. Copilot vindt dan per repo de `AGENTS.md`.

4. Laat de agent werken. Hij kan bestanden lezen en wijzigen en o.a. `kustomize build`, `yamllint` en `git status/diff/log` draaien.

5. **Review, commit en push doe je zelf** in een gewone terminal op de host. De container heeft geen push-rechten.

## 5. Controleren dat de afscherming werkt

In een terminal **in VS Code** binnen de container (niet via `podman exec`):

```bash
check-isolation; echo "exit=$?"

OK   geen secret-achtige variabelen
OK   SSH_AUTH_SOCK leeg
OK   DISPLAY leeg
OK   WAYLAND_DISPLAY leeg
OK   GIT_ASKPASS leeg
OK   KUBECONFIG=/dev/null
OK   geen X11/Wayland/ssh-agent/DBus-sockets
OK   geen container-socket
OK   mount /workspaces/oyster3-lorawan-gps-tracker-ttn
OK   geen andere mounts onder /workspaces
OK   geen vscode-cachevolume
OK   geen $HOME, ~/git of dotdirs van host gemount
OK   geen capabilities
OK   no-new-privileges
OK   seccomp actief
OK   SELinux container_t
OK   uid 1000
OK   geen verboden tools
OK   geen credential-bestanden in $HOME
OK   geen git credential helper (global)
OK   geen git credential helper (system)
OK   systeempaden niet schrijfbaar
WARN BROWSER gezet (URL's openen in host-browser)
WARN VSCODE_IPC_HOOK_CLI (code-CLI naar host-UI)
WARN REMOTE_CONTAINERS_IPC (Dev Containers-IPC naar host)
WARN MCP-socket(s) in /tmp
WARN internet bereikbaar (egress open)
---
RESULTAAT: geen FOUT, wel WARN (bekende restrisico's)
exit=0
```

- `OK` – in orde
- `WARN` – bekend restrisico (bijvoorbeeld internet bereikbaar, URL's openen in je host-browser); zie PROJECT.md
- `FOUT` – de afscherming is gebroken; stop en zoek uit waarom

Een intern doel meetesten (bereikbaar = `FOUT`):

```bash
CHECK_INTERNAL="api.<cluster>:6443" check-isolation
```

Op de host:

```bash
CID=$(podman ps -q --filter label=devcontainer.local_folder=$HOME/agent-sandbox)
podman inspect $CID --format '{{.ProcessLabel}} | {{json .HostConfig.SecurityOpt}}'   # container_t, geen label=disable
podman inspect $CID --format '{{json .Mounts}}'                                       # alleen je gekozen repo's
```

## Problemen oplossen

| Melding | Oorzaak | Oplossing |
|---|---|---|
| `agent-sandbox: … is gezet – start via ~/agent-sandbox/code-agent.sh` | VS Code niet via `code-agent.sh` gestart | Alle agent-vensters sluiten, `code-agent.sh` starten |
| `select-repos: gevoelige bestanden in <repo>` | Repo bevat mogelijk secrets | Bestanden weghalen, of bewust `--force` |
| Build faalt op `COPY …` | Bestand ontbreekt in `.devcontainer/` | `podman build` los draaien (stap 3) en fout lezen |
| Oude instellingen of mounts actief | "Reopen" hergebruikte bestaande container | **Rebuild and Reopen in Container** |
| Log toont `--docker-path podman` i.p.v. `podman-agent.sh` | Host-instellingen niet gekopieerd | Stap 1.2 opnieuw, VS Code herstarten |

## Bestanden

| Bestand | Functie |
|---|---|
| `code-agent.sh` | Start de aparte VS Code met schone omgeving; optioneel repo-namen |
| `select-repos.sh`, `repos.conf`, `repos.deny` | Repo's kiezen, huidige keuze, altijd geweigerde repo's |
| `settings.host.json` | Bron voor de host-instellingen van het agentprofiel |
| `podman-agent.sh` | podman-wrapper: houdt SELinux aan in de container |
| `guard-host-env.sh` | Weigert starten vanuit een VS Code met tokens, ssh-agent of X11 |
| `.devcontainer/` | Containerfile, `devcontainer.json`, workspace-bestand, `check-isolation.sh` |

Deze map wordt bewust **niet** in de container gemount, zodat de agent zijn eigen afscherming niet kan aanpassen.
