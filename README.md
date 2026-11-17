# agent-sandbox

Een afgeschermde VS Code Dev Container waarin AI-agents (GitHub Copilot) in een paar gekozen git-repo's kunnen werken, **zonder** toegang tot je tokens, ssh-agent, `~/.kube`, sudo of je andere repo's.

- Waarom en welke besluiten: [PROJECT.md](PROJECT.md)
- Hoe het werkt en het dreigingsmodel: [ARCHITECTURE.md](ARCHITECTURE.md)

## In het kort

```bash
~/agent-sandbox/code-agent.sh repo-a             # repo kiezen en aparte VS Code starten
# in VS Code: F1 → Dev Containers: Rebuild and Reopen in Container
# in de container-terminal (Terminal → New Terminal of Ctrl+Shift+`):
check-isolation                                  # moet eindigen met "geen FOUT"
```

## 1. Eenmalig instellen

De sandbox gebruikt een **aparte** VS Code-instantie met een eigen profiel en eigen extensies. Dat kan VS Code **stable** (standaard) of **Insiders** zijn. Je gewone VS Code blijft ongemoeid.

| Editie | Programma | Profiel | Extensies |
|---|---|---|---|
| stable (standaard) | `code` | `~/.config/Code-agent` | `~/.vscode-agent/extensions` |
| Insiders | `code-insiders` | `~/.config/Code-Insiders-agent` | `~/.vscode-insiders-agent/extensions` |

Richt per editie die je wilt gebruiken het profiel in (Dev Containers-extensie + host-instellingen uit `settings.host.json`):

```bash
~/agent-sandbox/setup-agent-profile.sh --stable
~/agent-sandbox/setup-agent-profile.sh --insiders     # alleen als je ook Insiders gebruikt
```

Draai dit opnieuw na elke wijziging van `settings.host.json`. `code-agent.sh` weigert te starten zolang het profiel afwijkt (melding: `profiel … wijkt af van settings.host.json`). Wijzig instellingen van het agentprofiel dus in `settings.host.json`, niet in VS Code zelf.

> De sandbox moet in `~/agent-sandbox` staan (clone hem daarheen). `settings.host.json` gebruikt `${HOME}`; `setup-agent-profile.sh` vult dat in, want VS Code doet dat zelf niet voor `dev.containers.dockerPath`. De container krijgt jouw UID/GID (`code-agent.sh` geeft ze door); root wordt geweigerd.

### Editie kiezen

```bash
echo stable   > ~/agent-sandbox/edition.conf     # standaard-editie vastleggen (of: insiders)
~/agent-sandbox/code-agent.sh                    # start de standaard-editie
~/agent-sandbox/code-agent.sh --insiders         # eenmalig de andere editie
~/agent-sandbox/code-agent.sh --stable repo-a        # editie en repo's tegelijk
```

Beide edities gebruiken dezelfde container, repo-keuze en afscherming. Copilot Chat is in beide ingebouwd.

### Netwerk met of zonder http-proxy

Zonder proxy hoef je niets te doen. Achter een http-proxy (zonder authenticatie): zet `http_proxy`/`https_proxy`/`no_proxy` (of de hoofdletter-varianten) in de shell waaruit je `setup-agent-profile.sh` en `code-agent.sh` start. Alleen deze variabelen gaan mee door de schone omgeving; podman geeft ze door aan image-pull, build en container.

Een proxy-URL met gebruikersnaam/wachtwoord (`http://user:pass@…`) wordt geweigerd: die zou in de container zichtbaar worden.

## 2. Git-repo's kiezen

De container ziet **alleen** de repo's die je kiest; elke repo uit de bronmap (standaard `~/git`) verschijnt als `/workspaces/<repo>`. Nooit de hele bronmap.

```bash
~/agent-sandbox/select-repos.sh repo-a                  # één repo
~/agent-sandbox/select-repos.sh repo-a repo-b           # meerdere repo's
~/agent-sandbox/select-repos.sh                         # huidige keuze tonen
```

Of in één keer met starten: `~/agent-sandbox/code-agent.sh repo-a repo-b`.

Staan je repo's niet in `~/git`? Zet de bronmap, relatief aan je home directory, in `repo-root.conf` (bijvoorbeeld `echo src/team > ~/agent-sandbox/repo-root.conf`) en kies daarna opnieuw je repo's. Absolute paden, `..` en je home directory zelf worden geweigerd.

`select-repos.sh` past `.devcontainer/devcontainer.json` en `.devcontainer/tst.code-workspace` aan, schrijft de keuze naar `repos.conf` en toont de wijziging. Pas het blok tussen `// BEGIN repos` en `// END repos` niet met de hand aan.

Het script **weigert** een repo als:

- de naam ongeldig is (bijvoorbeeld `../x`) of de map niet bestaat;
- het een symlink is of buiten de bronmap wijst;
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
- `openssl3-libs` en `ca-certificates`, nodig voor Copilot in de container;
- **niet** aanwezig: `ssh`, `curl`, `wget`, `sudo`, `oc`, `kubectl`, `helm`, `ansible`. De build **faalt** als een van deze toch in de image zit (bijvoorbeeld via de basisimage);
- gebruiker `agent` met jouw UID/GID (standaard 1000), plus `/usr/local/bin/check-isolation`.

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

   > **Chat pas ná deze stap.** In het venster vóór "Reopen in Container" draait Copilot nog op de host, met toegang tot je bestanden (zonder tokens of ssh-agent).

3. Bij meerdere repo's: **File → Open Workspace from File… → `/opt/tst.code-workspace`**. Copilot vindt dan per repo de `AGENTS.md`.

4. Laat de agent werken. Hij kan bestanden lezen en wijzigen en o.a. `kustomize build`, `yamllint` en `git status/diff/log` draaien.

5. **Review, commit en push doe je zelf** in een gewone terminal op de host. De container heeft geen push-rechten.

## 5. Controleren dat de afscherming werkt

In een terminal **in VS Code** binnen de container (niet via `podman exec`). Na het openen toont het terminalpaneel eerst het logtabblad "Dev Containers"; dat heeft geen prompt. Open een shell met **`+`** of **Ctrl+Shift+`**.

```bash
[agent@agent-sandbox]$ check-isolation; echo "exit=$?"

OK   geen secret-achtige variabelen
OK   SSH_AUTH_SOCK leeg
OK   DISPLAY leeg
OK   WAYLAND_DISPLAY leeg
OK   GIT_ASKPASS leeg
OK   KUBECONFIG=/dev/null
OK   geen X11/Wayland/ssh-agent/DBus-sockets
OK   geen container-socket
OK   mount /workspaces/repo-a
OK   geen andere mounts onder /workspaces
OK   geen vscode-cachevolume
OK   geen $HOME, ~/git of dotdirs van host gemount
OK   bron van elke repo-mount is de repo zelf
OK   geen capabilities
OK   no-new-privileges
OK   seccomp actief
OK   SELinux container_t
OK   uid 1000 (geen root)
OK   uid 1000 is eigenaar van /workspaces/repo-a
OK   geen verboden tools
OK   geen credential-bestanden in $HOME
OK   geen git credential helper (global)
OK   geen git credential helper (system)
OK   systeempaden niet schrijfbaar
WARN BROWSER gezet (URL's openen in host-browser)
WARN VSCODE_IPC_HOOK_CLI (code-CLI naar host-UI)
WARN REMOTE_CONTAINERS_IPC (Dev Containers-IPC naar host)
WARN MCP-socket(s) in /tmp
WARN host.containers.internal:22 bereikbaar
WARN host.containers.internal:8080 bereikbaar
WARN egress via proxy proxy.example:8080
---
RESULTAAT: geen FOUT, wel WARN (bekende restrisico's)
exit=0
```

- `OK` – in orde
- `WARN` – bekend restrisico (bijvoorbeeld URL's openen in je host-browser, internet of proxy bereikbaar, poorten op de host bereikbaar); zie PROJECT.md (B-16). Zonder proxy zie je `internet bereikbaar (egress open)` in plaats van `egress via proxy`; welke host-poorten verschijnen, hangt af van wat er op je host luistert
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
| Terminal geeft geen prompt, alleen elke minuut `Extensions cache, remote removals: None` | Dat is het logtabblad "Dev Containers", geen shell | Nieuwe terminal: `+` in het terminalpaneel of Ctrl+Shift+` |
| `profiel … wijkt af van settings.host.json` | Profiel verouderd of instelling in VS Code gewijzigd | `setup-agent-profile.sh --<editie>` |
| `Dev Containers ontbreekt in …` | Profiel nog niet ingericht | `setup-agent-profile.sh --<editie>` |
| Copilot toont geen modellen in de container | Image zonder `openssl3-libs` (oude build) | **Rebuild Container** |
| `setup-agent-profile.sh`: `AggregateError [ETIMEDOUT]`, of Rebuild blijft hangen na `Resolving Remote` (`podman pull`) | Netwerk zonder directe egress en proxyvariabelen niet gezet in de shell waaruit je startte | Proxyvariabelen zetten (zie *Netwerk met of zonder http-proxy*), script opnieuw draaien; bij hangende Rebuild eerst agent-venster sluiten |
| `deze map moet ~/agent-sandbox zijn` | Repo elders gecloned | Verplaatsen of clonen naar `~/agent-sandbox` |
| `AGENT_UID/AGENT_GID ontbreken of wijken af` | VS Code niet (opnieuw) via `code-agent.sh` gestart, bijvoorbeeld een venster van vóór een update | Alle agent-vensters sluiten, `code-agent.sh` starten |
| `repo-root.conf: ongeldig pad` | Absoluut pad, `..` of lege naam | Pad relatief aan je home directory, bijvoorbeeld `git` |
| `… bevat credentials (@); niet ondersteund` | Proxy-URL met gebruikersnaam/wachtwoord | Proxy zonder authenticatie gebruiken (proxy met authenticatie wordt niet ondersteund) |
| Build faalt met `FOUT: verboden tool …` | Basisimage bevat een verboden tool | Pakket uit de melding toevoegen aan de `rpm -e`-lijst in de Containerfile |

## Wijzigingen committen

Je eigen repo-keuze (`repos.conf`, het repo-blok in `devcontainer.json`, `tst.code-workspace`) hoort niet in git. In de repo staat een neutraal voorbeeld (`voorbeeld-repo`); `repo-root.conf` staat in `.gitignore`.

Zet eenmalig per clone de pre-commit hook aan. Die weigert een commit met een eigen repo-keuze, `repo-root.conf` of je home-pad:

```bash
git -C ~/agent-sandbox config core.hooksPath .githooks
```

Zet vóór elke commit het voorbeeld opnieuw in de git-index; je werkkopie blijft ongewijzigd:

```bash
cd ~/agent-sandbox
git add -A
./select-repos.sh --stage-example     # overschrijft alleen de staged versie van de drie bestanden
git diff --cached                     # controleren: geen eigen repo-namen of paden
git commit
```

`git status` toont je eigen repo-keuze daarna als lokaal gewijzigd; dat is de bedoeling.

## Bestanden

| Bestand | Functie |
|---|---|
| `code-agent.sh` | Start de aparte VS Code (stable/Insiders) met schone omgeving; optioneel `--stable`/`--insiders` en repo-namen |
| `setup-agent-profile.sh`, `edition.sh`, `edition.conf` | Agentprofiel per editie inrichten, editie bepalen, standaard-editie |
| `select-repos.sh`, `repos.conf`, `repos.deny`, `repo-root.conf` | Repo's kiezen, huidige keuze, altijd geweigerde repo's, optionele bronmap (standaard `~/git`) |
| `settings.host.json` | Sjabloon (met `${HOME}`) voor de host-instellingen van het agentprofiel |
| `podman-agent.sh` | podman-wrapper: houdt SELinux aan in de container |
| `guard-host-env.sh` | Weigert starten vanuit een VS Code met tokens, ssh-agent of X11 |
| `.devcontainer/` | Containerfile, `devcontainer.json`, workspace-bestand, `check-isolation.sh` |
| `AGENTS.md` | Regels voor AI-agents die aan déze repo werken (op de host) |
| `.githooks/pre-commit`, `.gitignore` | Houden je repo-keuze, `repo-root.conf` en home-pad uit git |

Deze map wordt bewust **niet** in de container gemount, zodat de agent zijn eigen afscherming niet kan aanpassen.
