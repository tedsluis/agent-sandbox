# PROJECT – agent-sandbox

## Doel

Een geïsoleerde werkomgeving op de Fedora-werkplek waarin AI-agents (GitHub Copilot, later ook Claude) code in de tst-repositories kunnen lezen, wijzigen en valideren, **zonder** toegang tot de secrets en rechten van de gebruiker.

Begrenzing gebeurt technisch (container, mounts, ontbrekende tools en credentials), niet via regels in een AGENTS.md. AGENTS.md-regels in de doelrepo's blijven bestaan als tweede lijn, maar zijn niet langer de enige bescherming.

## Context

- Werkplek: Fedora 45, gebruiker `tedsluis` (UID/GID 1000), GNOME op Wayland.
- Rol: platform-DevOps-engineer Linux/OpenShift. Werkt aan talloze projecten, (zie `~/git/`).
- Editor: VS Code **stable** (`code`, 1.146.0) en **Insiders** (`code-insiders`, 1.147.0-insider); sandbox standaard stable (B-11).
- Agents: GitHub Copilot Chat (ingebouwd in Insiders). Claude in VS Code wordt gebruikt om deze sandbox verder te ontwikkelen.

### Wat de agent NIET mag kunnen bereiken

| Bron op de host | Waar het staat | Risico |
|---|---|---|
| Bitbucket-token (pull/push) | omgevingsvariabele, versleuteld in `~/.bashrc`, ontsleuteld bij login met passphrase | pushen, repo's wijzigen |
| Confluence-token | idem | pagina's wijzigen |
| Ansible Vault-key | idem | inventory-secrets ontsleutelen |
| OpenSSL-encryptiekey | idem | versleutelde bestanden ontsleutelen |
| SSH-keys (OpenShift-nodes, Linux-servers) | versleuteld in `~/.ssh`, geladen in ssh-agent | inloggen op servers en nodes |
| OpenShift-tokens (admin, alle clusters) | `~/.kube` | volledige clusterbeheer |
| sudo | sudoers-regel | root op de werkplek |
| Grafische sessie | X11/Xwayland, Wayland-socket | toetsaanslagen meelezen/injecteren in andere vensters |

### Wat de agent WEL moet kunnen

- Bestanden lezen, aanmaken en wijzigen in de vele ~/git/ repo's.
- `kustomize build`, `yamllint`, `grep`/`find`/`diff`/`jq`.
- Lezende git-commando's (`status`, `diff`, `log`).

De gebruiker blijft in gewone terminals (GNOME Terminal) werken met secrets en ssh-agent geladen; die werkplek verandert niet.

## Gekozen oplossing

VS Code Dev Container op rootless podman, gestart vanuit een **aparte** VS Code-instantie met een schone omgeving. Zie `ARCHITECTURE.md` voor het ontwerp.

Overwogen alternatieven:

| Optie | Waarom (niet) gekozen |
|---|---|
| Dev Container (rootless podman) | **Gekozen.** Licht, reproduceerbaar, deelbaar met het team. |
| Aparte Linux-gebruiker + Remote-SSH naar `agent@localhost` | Klassieke DAC/RBAC, maar lastiger bestandsrechten op gedeelde repo's; agent forwarding moet expliciet uit. Terugvaloptie. |
| VM (libvirt/GNOME Boxes) + Remote-SSH | Sterkste grens (eigen kernel), maar zwaarder. Overwegen als netwerkscheiding hard moet. |
| Ingebouwde sandbox VS Code/Copilot (`chat.agent.sandbox.enabled`, bubblewrap) | Geen VM- of user-grens, dekt de bestandstools van de agent niet, geeft git/gh-credentials standaard door, netwerk standaard open. Alleen als extra laag. |
| Toolbox/Distrobox | Afgewezen: delen bewust home, omgeving en ssh-agent met de host. |

## Besluiten

| ID | Besluit | Reden |
|---|---|---|
| B-01 | De VS Code Server en alle extensies (Copilot) draaien in de container, niet op de host. | Copilot draait in de extension host; op de host ziet die je env, `~/.kube` en ssh-agent. |
| B-02 | Alleen expliciet gekozen repo's mounten, via `select-repos.sh` (vastgelegd in `repos.conf`; nu `genai-proxy`), niet `~/git` en niet `$HOME`. "Alle mappen" afgewezen op 2026-11-15. | `~/git` bevat ook andere repo's met o.a. een kubeconfig, `.env`-bestanden en vault-repo's; `$HOME` bevat `.kube`, `.ssh`, keyrings, credentials. `select-repos.sh` weigert repo's met gevoelige bestanden tenzij `--force`. |
| B-03 | Containerconfiguratie staat in `~/agent-sandbox`, buiten de mounts. | Anders kan de agent `devcontainer.json` aanpassen en bij een rebuild `~/.kube` mounten. |
| B-04 | Aparte VS Code-instantie via `code-agent.sh` met `env -i` en eigen `--user-data-dir`/`--extensions-dir`. | Geen `SSH_AUTH_SOCK`, tokens of `KUBECONFIG` om door te geven; `code` hergebruikt anders een draaiend venster met zijn omgeving. |
| B-05 | Credential-forwarding van de Dev Containers-extensie uit (gitconfig, git credential helper, docker credential helper, agent forwarding). | Anders kan de agent alsnog pushen met de rechten van de gebruiker. |
| B-06 | Geen `oc`, `kubectl`, `helm`, `ansible`, `ssh`, `sudo`, `curl` in de eindimage. | Wat er niet is, kan niet misbruikt worden. |
| B-07 | `--cap-drop=ALL`, `no-new-privileges`, `--userns=keep-id` (door de devcontainers CLI gezet; niet ook in `runArgs`, want twee `--userns` conflicteren), geen podman-socket. | Minimale rechten; bestanden op de host blijven van de gebruiker. |
| B-08 | SELinux-label met `,z` (gedeeld), niet `,Z`; SELinux-scheiding aan via `podman-agent.sh`, dat het door de CLI toegevoegde `label=disable` verwijdert. | `,Z` faalde op een bestand van een andere gebruiker in `~/git/keep`; `,z` laat host en container erbij. Zonder wrapper draait de container zonder SELinux-scheiding. |
| B-09 | VS Code native op Wayland (`--ozone-platform=wayland`), geen `DISPLAY`; Wayland-socket niet mounten. | X11-forwarding gaf de container toegang tot de grafische sessie van de host. |
| B-10 | Geen gedeeld cachevolume `vscode` (`dev.containers.cacheVolume: false`). | Gedeeld door alle dev containers; schrijfbaar volume = mogelijk de VS Code Server van andere containers aanpassen. Veroorzaakte ook de `extensionsCache: Not a directory`-fout. |
| B-11 | VS Code **stable én Insiders** voor de sandbox, gekozen met `edition.conf` of `--stable`/`--insiders`; standaard stable (gewijzigd 2026-11-16, was: alleen Insiders). | Stable is stabieler voor dagelijks werk; Insiders blijft beschikbaar voor nieuwe agentfuncties. Beide hebben Copilot Chat ingebouwd. |
| B-12 | Agent commit/pusht niet; de gebruiker reviewt en pusht vanuit een eigen terminal. | Geen push-credentials in de container. |
| B-13 | `initializeCommand` (`guard-host-env.sh`) weigert start/koppeling als de VS Code-instantie `SSH_AUTH_SOCK`, `DISPLAY`, `KUBECONFIG` of secret-achtige variabelen heeft. | Elke VS Code-instantie die `~/agent-sandbox` opent hergebruikt de container; audit 2026-11-15 vond ssh-agent- en X11-forwarding uit een instantie zonder `env -i`. |

## Status (laatst bijgewerkt 2026-11-15)

| Onderdeel | Status |
|---|---|
| Image bouwt (`podman build`) | ⏳ `podman build` 2026-11-15 15:3x OK, maar `curl` zat in de image (uit basisimage). Containerfile verwijdert nu curl/wget/ssh en faalt bij verboden tools; opnieuw bouwen |
| `podman run` met keep-id en `,z`-mount | ✅ container `4735d3a4c69e`: `uid=1000(agent)`, `uid_map` 1000→1000 (keep-id via CLI; inspect toont `UsernsMode: private`); `~/git/genai-proxy` gelabeld `container_file_t:s0` |
| Container start via Dev Containers, VS Code Server draait | ✅ `4735d3a4c69e` gestart via `code-agent.sh` + Rebuild (2026-11-15 14:40) |
| Geen ssh-agent, geen git credential helper, geen ssh/gpg in container | ✅ VS Code-terminal: `SSH_AUTH_SOCK`/`GIT_ASKPASS` leeg, geen `/tmp/vscode-ssh-auth-*`, geen `~/.gitconfig`, `check-isolation.sh` OK. Restkanalen `VSCODE_GIT_IPC_HANDLE`, `REMOTE_CONTAINERS_IPC` aanwezig (backlog 19) |
| Copilot Chat draait in de container | ⏳ `openssl3-libs` toegevoegd (libssl.so.3 voor Copilot-runtime); Marketplace-installatie van `GitHub.copilot-chat` (0.48.1) verwijderd, ingebouwde versie wordt gebruikt (stable 0.74.0, Insiders 0.75.x). Rebuild en modellenlijst nog toetsen |
| Repo-mounts (nu alleen `genai-proxy`) | ✅ inspect: één bind-mount `~/git/genai-proxy → /workspaces/genai-proxy`; `ls /workspaces` toont alleen `genai-proxy` |
| Repo's wisselen (`select-repos.sh`) | ✅ host-tests 2026-11-15: weigert `../x`, niet-bestaand, geen git-repo, treffers in `reg` (`*.pem`) en `Cachet` (`.env`); `genai-proxy` geeft identieke `devcontainer.json`; twee repo's genereren geldige JSON. Rebuild met `oyster3-lorawan-gps-tracker-ttn` OK (inspect + `check-isolation`) |
| X11/Wayland-forwarding uit | ✅ geen Wayland-mount (inspect), geen `/tmp/.X11-unix` en `/tmp/vscode-wayland-*`; Dev Containers-log nog nalopen op `X11 forwarding` |
| Geen cachevolume `vscode` | ✅ niet gemount in `4735d3a4c69e`; volume blijft bestaan voor `zealous_hamilton` (niet verwijderen) |
| Host-settings agentprofiel gelijk aan `settings.host.json` | ⏳ `code-agent.sh` controleert dit nu bij elke start; `setup-agent-profile.sh --stable` en `--insiders` nog draaien (beide profielen wijken af na commentaarwijziging 2026-11-16; stable-profiel was verouderd) |
| `extensionsCache`-fout opgelost | ✅ `/home/agent/.vscode-server-insiders/extensionsCache` is een map; VS Code Server draait |
| Multi-root workspace `/opt/tst.code-workspace` | ⏳ in image gekopieerd; openen in VS Code nog toetsen |
| SELinux-scheiding container | ✅ `ProcessLabel` `container_t:s0:c860,c1023`, `SecurityOpt` alleen `no-new-privileges` (geen `label=disable`) |
| B-04/B-13 schone omgeving | ✅ `env -i` aangetoond via guard-diagnose (geen tokens, `SSH_AUTH_SOCK`, `KUBECONFIG`); guard negeert dummy `DISPLAY=1`, blokkeert `DISPLAY` met `:` |
| Netwerk | ❌ open: DNS 8.8.8.8, host bereikbaar op `169.254.1.2` (bekend, backlog 4) |
| Rechten in container | ✅ `CapEff=0`, `NoNewPrivs=1` |
| Kanalen naar host-UI | ⚠️ `BROWSER` wordt in de VS Code-terminal door de server gezet (`remoteEnv` leeg werkt niet); `VSCODE_IPC_HOOK_CLI`, `REMOTE_CONTAINERS_IPC`, `VSCODE_GIT_IPC_HANDLE`, `/tmp/mcp-*` aanwezig (backlog 19) |
| `check-isolation.sh` in container gedraaid | ❌ nieuwe versie 2026-11-15: 1 FOUT (`curl` aanwezig, B-06), verder OK + 5 bekende WARN; opnieuw na rebuild |

## Backlog

1. **Direct (blokkerend):** ~~container `43c49715bd54` verwijderen~~ en ~~`settings.host.json` kopiëren~~ (gedaan 2026-11-15). Nog: `~/agent-sandbox` alleen via `code-agent.sh` openen; na backlog 14 Rebuild and Reopen, log controleren, `check-isolation.sh` draaien.
2. ~~Instellingsnamen bevestigen~~ **Gedaan 2026-11-15:** alle vier bestaan in `package.json` van 0.472.0 en 0.474.0 (`cacheVolume` bool, `mountWaylandSocket` bool, `dockerCredentialHelper` bool, `gitCredentialHelperConfigLocation` enum `system|global|none`).
3. ~~`check-isolation.sh` uitbreiden~~ **Gedaan 2026-11-15:** OK/WARN/FOUT, omgeving, sockets, mounts (`REPOS`), rechten/SELinux, tools, credentials, schrijfbaarheid, host-UI-kanalen, netwerk (`CHECK_INTERNAL`). Verplaatst naar `.devcontainer/` en meegebakken als `/usr/local/bin/check-isolation`. Nog: draaien na rebuild.
4. **Netwerk begrenzen:** egress via een allowlist-proxy op de host (GitHub/Copilot, eventueel Anthropic, registry) of interne ranges blokkeren met firewalld. Nu heeft de container vrij netwerk.
5. **Claude in de container** als agent naast Copilot: extensie toevoegen aan `devcontainer.json`, authenticatie en netwerk regelen. Claude Code leest `CLAUDE.md`, en `AGENTS.md` als er geen `CLAUDE.md` is.
6. **SELinux-labels herstellen** op de overige repo's in `~/git` (`restorecon -R ~/git`), na een test met heel `~/git` en `,z`.
7. **Git-repo van maken:** `~/agent-sandbox` onder versiebeheer, zodat wijzigingen reviewbaar zijn.
8. **Teamversie:** UID/GID en paden parametriseren (repolijst: gedaan via `select-repos.sh`; README.md: eerste versie 2026-11-15); README voor collega's.
9. **Image pinnen:** base-images op digest; kustomize-versie bewust bijwerken; eventueel `helm` toevoegen (`helm template` staat in de tst-AGENTS.md).
10. **Commits in de container:** besluiten of de agent lokaal mag committen of dat `.git` read-only moet.
11. **Host-hygiëne (los van de sandbox):** geen admin-token als standaard in `~/.kube` (impersonation of kortlevende tokens), Bitbucket-token splitsen in read en push, sudo met wachtwoord.
12. **Copilot-terminal-sandbox** (`chat.agent.sandbox.enabled`) als extra laag onderzoeken; werkt in dev containers alleen met extra opties die isolatie versoepelen.
13. **tst-AGENTS.md bijwerken:** verwijzen naar de sandbox en regels die nu technisch afgedwongen worden markeren.
14. ~~Repo-mounts echt configureren~~ **Geconfigureerd 2026-11-15:** alleen `genai-proxy`; `tst.code-workspace` aangemaakt. Nog testen.
15. ~~SELinux terug aan~~ **Geconfigureerd 2026-11-15:** `podman-agent.sh` als `dev.containers.dockerPath`. Nog testen (`ProcessLabel` = `container_t`).
16. ~~Openen vanuit verkeerde instantie voorkomen~~ **Geconfigureerd 2026-11-15:** `guard-host-env.sh` als `initializeCommand`, `remoteEnv` uitgebreid, `git.terminalAuthentication`/`github.gitAuthentication` uit. Nog testen.
17. **Volume `vscode` opruimen** na rebuild (eerst `podman ps -a --filter volume=vscode`); als onbetrouwbaar behandelen.
18. **autoApprove aanscherpen:** geen `find -exec/-delete`, `git diff/log` zonder ext-diff/`--output`, `kustomize build` zonder `--enable-exec`/plugins.
19. **Kanalen naar de host-UI inventariseren** (2026-11-15: `BROWSER` wordt door de VS Code Server in de terminal gezet ondanks `remoteEnv`; leegmaken sluit het kanaal niet, want `browser.sh` en `VSCODE_IPC_HOOK_CLI` blijven bruikbaar; toetsen of `REMOTE_CONTAINERS_IPC` nog git-credentials van de host levert met `gitCredentialHelperConfigLocation: none`): `BROWSER`, `VSCODE_IPC_HOOK_CLI`, `REMOTE_CONTAINERS_IPC`, `/tmp/mcp-*/mcp.sock`; opnemen in dreigingsmodel.
20. ~~ARCHITECTURE.md bijwerken~~ **Gedaan 2026-11-15** (§1–§7, §9).
21. **AI uit in lokaal agent-venster:** in het agent-venster vóór "Reopen in Container" draait de ingebouwde Copilot Chat lokaal op de host (2026-11-15: MCP-lock in `~/.copilot/ide/`); `remote.extensionKind` houdt dat niet tegen. Onderzoeken: `~/agent-sandbox/.vscode/settings.json` met instelling om chat/AI uit te zetten (naam TE BEVESTIGEN), of automatisch heropenen in container. Tot dan: alleen chatten ná Reopen in Container.

## Logboek van problemen

| Datum | Probleem | Oorzaak | Oplossing |
|---|---|---|---|
| 2026-11-10 | `An error occurred setting up the container` | Onbekend uit screenshot | `podman build` los draaien om de echte fout te zien |
| 2026-11-10 | Mogelijke build-fouten | `curl-minimal` mogelijk niet meer los beschikbaar; `microdnf remove shadow-utils` kan falen | Multi-stage build; curl alleen in de buildstage |
| 2026-11-10 | `failed to change selinux label ... ~/git/keep/state/db.sqlite3: operation not permitted` | `,Z` relabelt heel `~/git`, inclusief bestand van andere gebruiker | Alleen de zes repo's mounten, `,z` |
| 2026-11-10 | `cd: /home/agent/.vscode-server-insiders/extensionsCache: Not a directory` | Cachen naar gedeeld volume `vscode` | `dev.containers.cacheVolume: false`; map vooraf aanmaken in image |
| 2026-11-10 | `X11 forwarding: DISPLAY in container (:0) forwarded to local host` | `DISPLAY` aanwezig in VS Code-proces | Native Wayland zonder `DISPLAY`; `remoteEnv` DISPLAY leeg |
| 2026-11-10 | Wayland-socket gemount in container | Standaardgedrag Dev Containers | `dev.containers.mountWaylandSocket: false` |
| 2026-11-10 | Oude configuratie actief | "Reopen" startte bestaande container | "Rebuild and Reopen in Container" |
| 2026-11-15 | Audit: container ziet heel `~/git`, ssh-agent-socket, X11/Wayland-sockets, `vscode`-volume, gitconfig met credential helper | `devcontainer.json` mount `~/git`; host-settings niet gekopieerd; container vermoedelijk ook geopend zonder `env -i` | Container verwijderd, settings gekopieerd; verder backlog 14, 16, 17 |
| 2026-11-15 | `,z` zonder effect, SELinux uit in container | devcontainers CLI ≥ 0.80 voegt `--security-opt label=disable` toe bij podman | Backlog 15 |
| 2026-11-15 | Image-build breekt: `COPY tst.code-workspace ... no such file or directory` | Bestand ontbreekt in `.devcontainer/` | Bestand aangemaakt (backlog 14) |
| 2026-11-15 | Rebuild 14:1x gaf dezelfde fout | Rebuild gestart vóórdat de goedgekeurde diff was toegepast (log: `--docker-path podman`, oude STEP 8) | Diff toegepast 14:16; settings opnieuw kopiëren en opnieuw Rebuild |
| 2026-11-15 | Twee `--userns`-argumenten | CLI zet `--userns=keep-id` (remoteUser ≠ root), `runArgs` zette `--userns=keep-id:uid=1000,gid=1000` | `--userns` uit `runArgs` gehaald (B-07) |
| 2026-11-15 | Guard blokkeert start: `DISPLAY is gezet`, terwijl `SSH_AUTH_SOCK` leeg is | Iets voegt `DISPLAY` toe ná `env -i` in `code-agent.sh` (VS Code, Electron of shell-omgeving: TE BEVESTIGEN). Volume `vscode` is nog in gebruik door `zealous_hamilton` (niet verwijderen) | Guard toont nu bij fout `DISPLAY`-waarde, `VSCODE_CLI`, ouderproces en variabelenamen (geen waarden) |
| 2026-11-15 | Diagnose guard: `DISPLAY='1'`, naast `SSH_ASKPASS`, `SSH_ASKPASS_REQUIRE`, `VSCODE_SSH_ASKPASS_*`; geen tokens, `SSH_AUTH_SOCK`, `KUBECONFIG` of shellvariabelen | Dummy-`DISPLAY` voor ssh-askpass, gezet in de extension host (niet in open-source VS Code; vermoedelijk Dev Containers-extensie, TE BEVESTIGEN). B-04 (`env -i`) werkt | Guard blokkeert alleen `DISPLAY` met `:` (echte X-display); X11 na start toetsen in log en container |
| 2026-11-15 | `BROWSER` in VS Code-terminal gezet ondanks `remoteEnv` `""` | VS Code Server injecteert eigen `browser.sh` in terminalomgeving | Geaccepteerd als restkanaal; backlog 19 |
| 2026-11-15 | Oude `check-isolation.sh` gaf altijd OK voor clustertools en miste mounts, SELinux, X11/Wayland, netwerk | Beperkte eerste versie | Herschreven (backlog 3) en in image gebakken |
| 2026-11-15 | Repo's wisselen vereiste handwerk in `devcontainer.json` | Mounts liggen vast bij aanmaken container | `select-repos.sh` + `repos.conf`/`repos.deny`, markeringen in `devcontainer.json`, `AGENT_REPOS` voor `check-isolation`; `code-agent.sh` accepteert repo-namen |
| 2026-11-15 | `check-isolation`: `FOUT verboden tools: curl` | `curl` zit in basisimage `fedora-minimal:45`; Containerfile installeerde het niet maar verwijderde het ook niet; oude check testte niet op curl | Containerfile verwijdert `curl`/`curl-minimal`/`wget`/`openssh-clients` en faalt bij elke verboden tool (B-06) |
| 2026-11-15 | Copilot toont geen modellen in de container, wel lokaal | Copilot-runtime in container: `invalid proxy TLS configuration … install libssl.so.3`; `fedora-minimal:45` heeft alleen OpenSSL 4, host heeft `openssl3-libs` | `openssl3-libs` en `ca-certificates` in Containerfile |
| 2026-11-15 | `devcontainer.json` installeert `github.copilot-chat` 0.48.1 van Marketplace | Extensie expliciet in `customizations.vscode.extensions`, terwijl stable (0.74.0) en Insiders (0.75.x) hem ingebouwd hebben | Regel verwijderd (2026-11-16) |
| 2026-11-16 | Sandbox alleen voor Insiders; oud stable-profiel `~/.config/Code-agent` had verouderde instellingen (geen wrapper, geen `cacheVolume`/`mountWaylandSocket: false`) | Paden vast in `code-agent.sh` | `edition.sh`/`edition.conf`, `setup-agent-profile.sh`; `code-agent.sh` weigert bij afwijkend profiel; B-11 gewijzigd |
| 2026-11-16 | Test `select-repos.sh Cachet --force` schreef per ongeluk `Cachet` in de configuratie | Testfout van de agent | Direct teruggezet op `oyster3-lorawan-gps-tracker-ttn`; geen container gestart. `--force` werkt nu op elke positie |
