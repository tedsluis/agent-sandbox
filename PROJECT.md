# PROJECT – agent-sandbox

## Doel

Een geïsoleerde werkomgeving op de Fedora-werkplek waarin AI-agents (GitHub Copilot, later ook Claude) code in gekozen git-repositories kunnen lezen, wijzigen en valideren, **zonder** toegang tot de secrets en rechten van de gebruiker.

Begrenzing gebeurt technisch (container, mounts, ontbrekende tools en credentials), niet via regels in een AGENTS.md. AGENTS.md-regels in de doelrepo's blijven bestaan als tweede lijn, maar zijn niet langer de enige bescherming.

## Context

- Werkplek: Fedora 45, gewone gebruiker (UID/GID willekeurig, niet root; B-17), GNOME op Wayland.
- Rol: DevOps-/platformwerk aan veel git-repo's in één bronmap (standaard `~/git`, instelbaar met `repo-root.conf`).
- Editor: VS Code **stable** (`code`, 1.146.0) en **Insiders** (`code-insiders`, 1.146.0-insider of 1.147.0-insider, per werkplek: ARCHITECTURE §7); sandbox standaard stable (B-11).
- Agents: GitHub Copilot Chat (ingebouwd in stable en Insiders). Claude in VS Code wordt gebruikt om deze sandbox verder te ontwikkelen.

### Wat de agent NIET mag kunnen bereiken

| Bron op de host | Waar het staat | Risico |
|---|---|---|
| Token voor git-hosting (pull/push) | omgevingsvariabele in de login-shell | pushen, repo's wijzigen |
| Tokens voor andere diensten (wiki e.d.) | idem | pagina's wijzigen |
| Ansible Vault-key | idem | inventory-secrets ontsleutelen |
| OpenSSL-encryptiekey | idem | versleutelde bestanden ontsleutelen |
| SSH-keys (servers, clusternodes) | `~/.ssh`, geladen in ssh-agent | inloggen op servers en nodes |
| Kubernetes-/OpenShift-tokens | `~/.kube` | clusterbeheer |
| sudo | sudo-rechten van de gebruiker | root op de werkplek |
| Grafische sessie | X11/Xwayland, Wayland-socket | toetsaanslagen meelezen/injecteren in andere vensters |

### Wat de agent WEL moet kunnen

- Bestanden lezen, aanmaken en wijzigen in de gekozen repo's uit de bronmap (standaard `~/git`).
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
| B-02 | Alleen expliciet gekozen repo's mounten, via `select-repos.sh` (vastgelegd in `repos.conf`), niet `~/git` en niet `$HOME`. "Alle mappen" afgewezen op 2026-11-15. | `~/git` bevat ook andere repo's met o.a. een kubeconfig, `.env`-bestanden en vault-repo's; `$HOME` bevat `.kube`, `.ssh`, keyrings, credentials. `select-repos.sh` weigert repo's met gevoelige bestanden tenzij `--force`. |
| B-03 | Containerconfiguratie staat in `~/agent-sandbox`, buiten de mounts. | Anders kan de agent `devcontainer.json` aanpassen en bij een rebuild `~/.kube` mounten. |
| B-04 | Aparte VS Code-instantie via `code-agent.sh` met `env -i` en eigen `--user-data-dir`/`--extensions-dir`. | Geen `SSH_AUTH_SOCK`, tokens of `KUBECONFIG` om door te geven; `code` hergebruikt anders een draaiend venster met zijn omgeving. |
| B-05 | Credential-forwarding van de Dev Containers-extensie uit (gitconfig, git credential helper, docker credential helper, agent forwarding). | Anders kan de agent alsnog pushen met de rechten van de gebruiker. |
| B-06 | Geen `oc`, `kubectl`, `helm`, `ansible`, `ssh`, `sudo`, `curl`, `wget` in de eindimage; de build faalt als er een vindbaar is. | Wat er niet is, kan niet misbruikt worden. De basisimage bleek `curl` te bevatten (2026-11-15). |
| B-07 | `--cap-drop=ALL`, `no-new-privileges`, `--userns=keep-id` (door de devcontainers CLI gezet; niet ook in `runArgs`, want twee `--userns` conflicteren), geen podman-socket. | Minimale rechten; bestanden op de host blijven van de gebruiker. |
| B-08 | SELinux-label met `,z` (gedeeld), niet `,Z`; SELinux-scheiding aan via `podman-agent.sh`, dat het door de CLI toegevoegde `label=disable` verwijdert. | `,Z` faalde op een bestand van een andere gebruiker in een repo in `~/git`; `,z` laat host en container erbij. Zonder wrapper draait de container zonder SELinux-scheiding. |
| B-09 | VS Code native op Wayland (`--ozone-platform=wayland`), geen `DISPLAY`; Wayland-socket niet mounten. | X11-forwarding gaf de container toegang tot de grafische sessie van de host. |
| B-10 | Geen gedeeld cachevolume `vscode` (`dev.containers.cacheVolume: false`). | Gedeeld door alle dev containers; schrijfbaar volume = mogelijk de VS Code Server van andere containers aanpassen. Veroorzaakte ook de `extensionsCache: Not a directory`-fout. |
| B-11 | VS Code **stable én Insiders** voor de sandbox, gekozen met `edition.conf` of `--stable`/`--insiders`; standaard stable (gewijzigd 2026-11-16, was: alleen Insiders). | Stable is stabieler voor dagelijks werk; Insiders blijft beschikbaar voor nieuwe agentfuncties. Beide hebben Copilot Chat ingebouwd. |
| B-12 | Agent commit/pusht niet; de gebruiker reviewt en pusht vanuit een eigen terminal. | Geen push-credentials in de container. |
| B-13 | `initializeCommand` (`guard-host-env.sh`) weigert start/koppeling als de VS Code-instantie `SSH_AUTH_SOCK`, een X11-`DISPLAY` (met `:`), `KUBECONFIG` of secret-achtige variabelen heeft. | Elke VS Code-instantie die `~/agent-sandbox` opent hergebruikt de container; audit 2026-11-15 vond ssh-agent- en X11-forwarding uit een instantie zonder `env -i`. VS Code zet zelf een dummy `DISPLAY=1`. |
| B-14 | `code-agent.sh` start alleen als het agentprofiel gelijk is aan `settings.host.json` (na invullen van `${HOME}`, B-17) en Dev Containers geïnstalleerd is; instellingen wijzigen gaat via `settings.host.json` + `setup-agent-profile.sh`. | Een verouderd profiel (zonder wrapper, met Wayland-socket of cachevolume) heft SELinux- en mountscheiding ongemerkt op; gevonden in het oude stable-profiel (2026-11-16). |
| B-15 | Proxyvariabelen (`http_proxy`, `https_proxy`, `no_proxy`, ook in hoofdletters) gaan als enige extra variabelen door `env -i` (`edition.sh` → `PROXY_ENV`), alleen als ze gezet zijn; proxy-URL's met credentials (`@`) worden geweigerd (`edition.sh`, `guard-host-env.sh`, `check-isolation`). Geen `http.proxy` in `settings.host.json`. | Op een netwerk zonder directe egress liepen extensie-installatie (`ETIMEDOUT`) en `podman pull` (`SYN-SENT` naar de registry) vast doordat `env -i` de proxy wiste (2026-11-16). Zonder proxy verandert er niets; `settings.host.json` blijft systeemonafhankelijk (B-14 vergelijkt byte voor byte). Podman geeft de variabelen door aan pull, build en container. |
| B-16 | Netwerk van de container wordt niet verder begrensd (geen allowlist-proxy of firewall); restrisico geaccepteerd (2026-11-16, backlog 4 vervallen). Ook `chat.tools.terminal.autoApprove` blijft zoals het is (backlog 18 vervallen). | Copilot heeft internet nodig; de container heeft geen credentials voor interne systemen. Gemeten restrisico: egress via de proxy, domeinen uit `no_proxy` direct bereikbaar, host-poorten 22 en 8080 via `host.containers.internal`, `python3` (afhankelijkheid van `yamllint`) kan willekeurige verbindingen openen. |
| B-17 | Geen persoonlijke waarden in de gevolgde bestanden (teamversie, publieke repo): `settings.host.json` gebruikt `${HOME}` (Dev Containers vult dat in `dockerPath` niet zelf in; `edition.sh` → `render_settings` doet het bij kopiëren en vergelijken); de sandbox staat altijd in `~/agent-sandbox` (`edition.sh` weigert anders); `code-agent.sh` geeft `AGENT_UID`/`AGENT_GID` (`id -u`/`id -g`) door voor `build.args` (`${localEnv:AGENT_UID:1000}`), de guard eist ze, `check-isolation` controleert dat de agent-UID eigenaar is van de repo's en niet 0; bronmap relatief aan `$HOME` via `repo-root.conf` (standaard `git`); repo-keuze in git als neutraal voorbeeld (`select-repos.sh --stage-example`). | Met een andere UID dan 1000 kon `agent` de repo's niet lezen (keep-id); het vaste pad `/home/<gebruiker>` en de eigen repo-namen lekten naar GitHub. Gecontroleerd 2026-11-16: `~` wordt in Dev Containers 0.474.0 alleen voor het ssh-configpad uitgepakt; `${localEnv:VAR:default}` geeft de standaardwaarde als VAR ontbreekt (devcontainers CLI 0.90.0, functie `Sb`). |

## Status (laatst bijgewerkt 2026-11-16)

| Onderdeel | Status |
|---|---|
| Image bouwt (`podman build`) | ✅ curl verwijderd en build-check actief: `check-isolation` meldt "geen verboden tools" (output gebruiker 2026-11-16, in README) |
| `podman run` met keep-id en `,z`-mount | ✅ testcontainer: `uid=1000(agent)`, `uid_map` 1000→1000 (keep-id via CLI; inspect toont `UsernsMode: private`); gekozen repo gelabeld `container_file_t:s0` |
| Container start via Dev Containers, VS Code Server draait | ✅ gestart via `code-agent.sh` + Rebuild (2026-11-15, opnieuw 2026-11-16) |
| Geen ssh-agent, geen git credential helper, geen ssh/gpg in container | ✅ VS Code-terminal: `SSH_AUTH_SOCK`/`GIT_ASKPASS` leeg, geen `/tmp/vscode-ssh-auth-*`, geen `~/.gitconfig`, `check-isolation.sh` OK. Restkanalen `VSCODE_GIT_IPC_HANDLE`, `REMOTE_CONTAINERS_IPC` aanwezig (backlog 19) |
| Copilot Chat draait in de container | ✅ Insiders 2026-11-16: chat met Claude Opus werkt via de http-proxy; agent host draait in de container (`--type=agentHost`; renderer.log `[AgentHost:remote]`, `connectionKind: remote_extension_host`). `openssl3-libs` (libssl.so.3) en ingebouwde Copilot Chat (stable 0.74.0, Insiders 0.75.x) in plaats van Marketplace 0.48.1. Stable nog toetsen (backlog 22) |
| Repo-mounts (`repos.conf`) | ✅ getest met twee verschillende keuzes: alleen de gekozen repo's gemount (inspect + `check-isolation`) |
| Repo's wisselen (`select-repos.sh`) | ✅ host-tests 2026-11-15: weigert `../x`, niet-bestaand, geen git-repo, repo's met `*.pem` of `.env`; dezelfde keuze geeft identieke `devcontainer.json`; twee repo's genereren geldige JSON. Rebuild met een andere repo OK (inspect + `check-isolation`) |
| X11/Wayland-forwarding uit | ✅ geen Wayland-mount (inspect), geen `/tmp/.X11-unix` en `/tmp/vscode-wayland-*`; Dev Containers-log 2026-11-16: `X11 forwarding: DISPLAY not set on local host`, `SSH_AUTH_SOCK not set on local host` |
| Geen cachevolume `vscode` | ✅ niet gemount in de agent-container; volume `vscode` bestaat inmiddels niet meer (backlog 17) |
| Host-settings agentprofiel gelijk aan `settings.host.json` | ✅ werkplek met proxy, Insiders 2026-11-16: `code-agent.sh --insiders` startte (profielcontrole B-14 geslaagd), log toont `--docker-path …/podman-agent.sh`. ⏳ Werkplek zonder proxy: beide profielen wijken af (stable nog van 2026-11-10 zonder wrapper, geen Dev Containers; Insiders met oud commentaar en een UI-instelling); `code-agent.sh` weigert terecht, `setup-agent-profile.sh --stable` en `--insiders` draaien. Stable nog toetsen (backlog 22) |
| `extensionsCache`-fout opgelost | ✅ Insiders 2026-11-16: `redhat.vscode-yaml` geïnstalleerd en naar de cache gekopieerd; voor stable (`~/.vscode-server`) aangemaakt, nog toetsen (backlog 22) |
| Multi-root workspace `/opt/tst.code-workspace` | ⏳ in image gekopieerd; openen in VS Code nog toetsen |
| SELinux-scheiding container | ✅ `ProcessLabel` `container_t:s0:c860,c1023`, `SecurityOpt` alleen `no-new-privileges` (geen `label=disable`); opnieuw gemeten 2026-11-16 (`container_t:s0:c260,c629`) |
| B-04/B-13 schone omgeving | ✅ `env -i` aangetoond via guard-diagnose (geen tokens, `SSH_AUTH_SOCK`, `KUBECONFIG`); guard negeert dummy `DISPLAY=1`, blokkeert `DISPLAY` met `:` |
| Netwerk | ⚠️ geaccepteerd (B-16): netwerk `pasta`; egress via proxy, `no_proxy`-domeinen direct, host-poorten 22 en 8080 bereikbaar via `host.containers.internal` (2026-11-16); eerder ook DNS 8.8.8.8 en host op `169.254.1.2` |
| Proxy-systemen (B-15) | ✅ Insiders 2026-11-16: Rebuild via proxy (pull, `dnf`/`microdnf`, kustomize, VS Code Server, extensie) zonder timeouts; proxyvariabelen in container (podman geeft ze door, `podman inspect` `.Config.Env`); `git ls-remote https://github.com/…` OK; Copilot (Claude Opus) OK; `check-isolation`: `WARN egress via proxy`. Nog: stable en test zonder proxy (backlog 23) |
| Publicatie zonder persoonlijke waarden (B-17) | ❌ HEAD `11b70ce` (gepusht) bevat eigen repo-namen in `repos.conf`, `devcontainer.json` en `tst.code-workspace`; eerdere commits bevatten persoonlijke details (backlog 8a). Pre-commit hook en `.gitignore` toegevoegd; fix-commit en `git config core.hooksPath .githooks` door gebruiker |
| Rechten in container | ✅ `CapEff=0`, `NoNewPrivs=1`, seccomp, uid 1000 |
| Parametrisering teamversie (B-17) | ✅ 2026-11-16 Rebuild (Insiders): guard liet start toe (dus `AGENT_UID`/`AGENT_GID` gezet), image-historie `USER_UID=1000`/`USER_GID=1000`, `container_t`, `check-isolation` geen FOUT met nieuwe OK's "uid 1000 (geen root)", "eigenaar van /workspaces/<repo>" en "bron van elke repo-mount is de repo zelf". Eerder: host-tests 2026-11-16 in wegwerpkopie met nep-`HOME`: `select-repos.sh` geeft voor dezelfde keuze identieke bestanden, weigert ongeldige `repo-root.conf` (`../etc`, `/etc`, `git/../..`), `--stage-example` wijzigt alleen de git-index; `render_settings` gelijk aan het stable-profiel; guard weigert zonder of met afwijkende `AGENT_UID`; `edition.sh` weigert buiten `~/agent-sandbox`. Nog: test met een andere UID dan 1000 (bewijst dat build-args werken; bij UID 1000 is standaard en doorgegeven waarde gelijk) |
| Editie stable end-to-end | ⏳ stable 1.146.0 geïnstalleerd; profiel inrichten, Rebuild, `check-isolation` en Copilot-modellen nog toetsen |
| Copilot lokaal in agent-venster | ❌ draait op de host vóór Reopen in Container (backlog 21); ná Reopen gebruikt de chat in het containervenster de agent host in de container (2026-11-16) |
| Kanalen naar host-UI | ⚠️ `BROWSER` wordt in de VS Code-terminal door de server gezet (`remoteEnv` leeg werkt niet); `VSCODE_IPC_HOOK_CLI`, `REMOTE_CONTAINERS_IPC`, `VSCODE_GIT_IPC_HANDLE`, `/tmp/mcp-*` aanwezig (backlog 19) |
| `check-isolation.sh` in container gedraaid | ✅ 2026-11-16 na rebuild: geen FOUT, 5 bekende WARN (host-UI-kanalen, internet), `exit=0` (output in README). 2026-11-16 met proxy (Insiders): 7 WARN, nieuw `host.containers.internal:22` en `:8080` bereikbaar (geaccepteerd, B-16) |

## Backlog

1. ~~Direct (blokkerend)~~ **Gedaan 2026-11-16:** oude container verwijderd, settings gekopieerd, Rebuild via `code-agent.sh`, `check-isolation` zonder FOUT.
2. ~~Instellingsnamen bevestigen~~ **Gedaan 2026-11-15:** alle vier bestaan in `package.json` van 0.472.0 en 0.474.0 (`cacheVolume` bool, `mountWaylandSocket` bool, `dockerCredentialHelper` bool, `gitCredentialHelperConfigLocation` enum `system|global|none`).
3. ~~`check-isolation.sh` uitbreiden~~ **Gedaan 2026-11-15:** OK/WARN/FOUT, omgeving, sockets, mounts (`AGENT_REPOS`), rechten/SELinux, tools, credentials, schrijfbaarheid, host-UI-kanalen, netwerk (`CHECK_INTERNAL`). Meegebakken als `/usr/local/bin/check-isolation`; gedraaid 2026-11-16.
4. ~~Netwerk begrenzen~~ **Vervallen 2026-11-16 (besluit gebruiker, B-16):** restrisico geaccepteerd. Oorspronkelijk: egress via een allowlist-proxy op de host (GitHub/Copilot, eventueel Anthropic, registry) of interne ranges blokkeren met firewalld. Meten en verkleinen van het restrisico: backlog 24.
5. **Claude in de container** als agent naast Copilot: extensie toevoegen aan `devcontainer.json`, authenticatie en netwerk regelen. Claude Code leest `CLAUDE.md`, en `AGENTS.md` als er geen `CLAUDE.md` is.
6. **SELinux-labels herstellen (uitgesteld 2026-11-16, besluit gebruiker):** ansible-navigator mount in een eigen podman-container de hele home directory; effect van herlabelen daarop niet onderzocht; geen risico voor de sandbox (die mount alleen de gekozen repo's met `,z`). Details voor later, in `~/git` (uitvoeren door de gebruiker; agents mogen geen `restorecon`). Gemeten 2026-11-16: ~50.700 bestanden `container_file_t:s0:c1022,c1023` (oude `,Z`-poging), ~1.700 `container_file_t:s0` (repo's ooit met `,z` gemount), verwacht `user_home_t:s0` (`matchpathcon`); alle bestanden van de gebruiker, dus geen sudo nodig. Let op: (a) eerst het agent-venster sluiten, anders verliest de draaiende sandbox toegang; bij de volgende Rebuild zet `,z` de gekozen repo's terug op `container_file_t:s0`; (b) andere (niet-sandbox) containers die bestanden uit `~/git` zonder `:z` mounten, werken nu alleen door het toevallige label en krijgen na `restorecon` *permission denied* bij herstart: `:z` aan hun mount toevoegen. Stappen: `restorecon -RFn -v ~/git | head` (droog), `restorecon -RF ~/git` (`-F` is nodig: `container_file_t` staat in `/etc/selinux/targeted/contexts/customizable_types`, zonder `-F` slaat restorecon het stil over), `find ~/git -xdev -printf '%Z\n' | sort | uniq -c` (alleen `user_home_t`), `code-agent.sh` + Rebuild. Testregel: daarna `ls -Zd ~/git/*/` toont `container_file_t:s0` alleen voor de repo's uit `repos.conf`, en `check-isolation` geeft geen FOUT.
7. ~~Git-repo van maken~~ **Gedaan:** `~/agent-sandbox` staat onder versiebeheer (remote `github.com/tedsluis/agent-sandbox`, publiek; let op backlog 8 vóór elke push).
8. **Teamversie en publicatie:** *grotendeels gedaan 2026-11-16 (B-17):* `${HOME}` in `settings.host.json` (ingevuld door `setup-agent-profile.sh`), `AGENT_UID`/`AGENT_GID` voor de image-build, bronmap via `repo-root.conf`, neutrale voorbeeldwaarden via `select-repos.sh --stage-example`, persoonlijke details uit de documentatie. Eerder gedaan: repo-keuze (`select-repos.sh`), editiekeuze (`edition.conf`), README.md. Gedaan 2026-11-16: pre-commit hook (`.githooks/pre-commit`, activeren met `git config core.hooksPath .githooks`) en `.gitignore`. Open: (a) **git-historie**: de repo is publiek en de eerdere commits bevatten nog persoonlijke details (gebruikersnaam, repo-namen, beschrijving van de eigen werkplek); besluiten: accepteren of herschrijven (`git filter-repo` + force-push, door de gebruiker); (b) `LICENSE` kiezen (zonder licentie: alle rechten voorbehouden); (c) README: sectie Vereisten/Installatie; (d) eventueel `tst.code-workspace` hernoemen; (e) testen met een andere UID dan 1000 en met `repo-root.conf`.
9. **Image pinnen:** base-images op digest; kustomize-versie bewust bijwerken; eventueel `helm` toevoegen (`helm template` staat in de tst-AGENTS.md).
10. **Commits in de container:** besluiten of de agent lokaal mag committen of dat `.git` read-only moet.
11. ~~Host-hygiëne~~ **Vervallen 2026-11-16 (besluit gebruiker):** buiten de scope van de sandbox. Oorspronkelijk: tokens op de host beperken (kortlevend, alleen-lezen waar mogelijk) en sudo met wachtwoord.
12. ~~Copilot-terminal-sandbox~~ **Vervallen 2026-11-16:** al afgewezen als hoofdoptie (zie *Gekozen oplossing*). Oorspronkelijk: `chat.agent.sandbox.enabled` als extra laag onderzoeken; werkt in dev containers alleen met extra opties die isolatie versoepelen.
13. **tst-AGENTS.md bijwerken (buiten deze repo, oppakken in de tst-repo):** verwijzen naar de sandbox en regels die nu technisch afgedwongen worden markeren.
14. ~~Repo-mounts echt configureren~~ **Gedaan 2026-11-15:** via `select-repos.sh`; getest met twee repo's.
15. ~~SELinux terug aan~~ **Gedaan 2026-11-15:** `podman-agent.sh`; `container_t` gemeten.
16. ~~Openen vanuit verkeerde instantie voorkomen~~ **Gedaan 2026-11-15:** guard (B-13) en profielcontrole (B-14); guard blokkeerde in de praktijk. Nog: test door `~/agent-sandbox` vanuit gewone VS Code te openen.
17. ~~Volume `vscode` opruimen~~ **Gedaan (vastgesteld 2026-11-16):** `podman volume ls` toont geen `vscode` meer, de andere dev container die het gebruikte bestaat niet meer. Oorspronkelijk: werd nog gebruikt door een andere dev container; de agent-container mount het niet meer. Opruimen als die container weg is (`podman ps -a --filter volume=vscode`).
18. ~~autoApprove aanscherpen~~ **Vervallen 2026-11-16 (besluit gebruiker, B-16):** restrisico geaccepteerd. Oorspronkelijk: geen `find -exec/-delete`, `git diff/log` zonder ext-diff/`--output`, `kustomize build` zonder `--enable-exec`/plugins.
19. **Kanalen naar de host-UI inventariseren** (2026-11-15: `BROWSER` wordt door de VS Code Server in de terminal gezet ondanks `remoteEnv`; leegmaken sluit het kanaal niet, want `browser.sh` en `VSCODE_IPC_HOOK_CLI` blijven bruikbaar; toetsen of `REMOTE_CONTAINERS_IPC` nog git-credentials van de host levert met `gitCredentialHelperConfigLocation: none`): `BROWSER`, `VSCODE_IPC_HOOK_CLI`, `REMOTE_CONTAINERS_IPC`, `/tmp/mcp-*/mcp.sock`; opnemen in dreigingsmodel.
20. ~~ARCHITECTURE.md bijwerken~~ **Gedaan 2026-11-15** (§1–§7, §9).
21. **AI uit in lokaal agent-venster:** in het agent-venster vóór "Reopen in Container" draait de ingebouwde Copilot Chat lokaal op de host (2026-11-15: MCP-lock in `~/.copilot/ide/`); `remote.extensionKind` houdt dat niet tegen. Onderzoeken: `~/agent-sandbox/.vscode/settings.json` met instelling om chat/AI uit te zetten (naam TE BEVESTIGEN), of automatisch heropenen in container. Tot dan: alleen chatten ná Reopen in Container. 2026-11-16 bevestigd: ná Reopen draait de agent host in de container (`--type=agentHost`, renderer.log `[AgentHost:remote]`, `connectionKind: remote_extension_host`); een chat in een lokaal venster (`connectionKind: local`) draait `copilot-runtime` op de host.
22. **Editie stable end-to-end toetsen:** `setup-agent-profile.sh --stable`, `code-agent.sh`, Rebuild, `check-isolation`, Copilot-modellen; idem `--insiders`. Daarna §7 ARCHITECTURE bijwerken (versies in container, o.a. `openssl3-libs`).
23. **Proxy end-to-end toetsen (B-15):** *Insiders met proxy gedaan 2026-11-16* (Rebuild, inspect, `git ls-remote`, Copilot Claude Opus, `check-isolation`); podman geeft de variabelen door aan de container. Open: stable, `setup-agent-profile.sh` zonder `ETIMEDOUT` vastleggen, test zonder proxy. Oorspronkelijk plan: met proxy: `setup-agent-profile.sh --insiders` zonder `ETIMEDOUT`, Rebuild zonder timeouts (pull, `dnf`/`microdnf`, kustomize, VS Code Server), `podman inspect … .Config.Env` bevat proxyvariabelen, Copilot toont modellen, `check-isolation` meldt `WARN egress via proxy`. Zonder proxy (`env -u` op alle zes): gedrag als vóór B-15. Doorgifte door podman (`--http-proxy`, `containers.conf` `http_proxy = true`) TE BEVESTIGEN; zo niet, `remoteEnv` met `${localEnv:HTTPS_PROXY}`. Proxy kan later de allowlist-proxy van backlog 4 worden (vervallen, B-16).
24. **Restrisico B-16 meten en verkleinen (optioneel):** host-poorten 22 (sshd) en 8080 (dienst onbekend; op host: `ss -ltnp 'sport = :8080'`) bereikbaar via `host.containers.internal` (pasta); optie `--network=pasta:--no-map-gw` onderzoeken (TE BEVESTIGEN). `no_proxy` bevat interne domeinen (o.a. clusters) die direct gaan, buiten de proxy om: toetsen met `CHECK_INTERNAL="<cluster-api>:6443" check-isolation`. (Verplaatst uit backlog 4.)

## Logboek van problemen

| Datum | Probleem | Oorzaak | Oplossing |
|---|---|---|---|
| 2026-11-10 | `An error occurred setting up the container` | Onbekend uit screenshot | `podman build` los draaien om de echte fout te zien |
| 2026-11-10 | Mogelijke build-fouten | `curl-minimal` mogelijk niet meer los beschikbaar; `microdnf remove shadow-utils` kan falen | Multi-stage build; curl alleen in de buildstage |
| 2026-11-10 | `failed to change selinux label ... ~/git/<repo>/state/db.sqlite3: operation not permitted` | `,Z` relabelt heel `~/git`, inclusief bestand van andere gebruiker | Alleen de zes repo's mounten, `,z` |
| 2026-11-10 | `cd: /home/agent/.vscode-server-insiders/extensionsCache: Not a directory` | Cachen naar gedeeld volume `vscode` | `dev.containers.cacheVolume: false`; map vooraf aanmaken in image |
| 2026-11-10 | `X11 forwarding: DISPLAY in container (:0) forwarded to local host` | `DISPLAY` aanwezig in VS Code-proces | Native Wayland zonder `DISPLAY`; `remoteEnv` DISPLAY leeg |
| 2026-11-10 | Wayland-socket gemount in container | Standaardgedrag Dev Containers | `dev.containers.mountWaylandSocket: false` |
| 2026-11-10 | Oude configuratie actief | "Reopen" startte bestaande container | "Rebuild and Reopen in Container" |
| 2026-11-15 | Audit: container ziet heel `~/git`, ssh-agent-socket, X11/Wayland-sockets, `vscode`-volume, gitconfig met credential helper | `devcontainer.json` mount `~/git`; host-settings niet gekopieerd; container vermoedelijk ook geopend zonder `env -i` | Container verwijderd, settings gekopieerd; verder backlog 14, 16, 17 |
| 2026-11-15 | `,z` zonder effect, SELinux uit in container | devcontainers CLI ≥ 0.80 voegt `--security-opt label=disable` toe bij podman | Backlog 15 |
| 2026-11-15 | Image-build breekt: `COPY tst.code-workspace ... no such file or directory` | Bestand ontbreekt in `.devcontainer/` | Bestand aangemaakt (backlog 14) |
| 2026-11-15 | Rebuild 14:1x gaf dezelfde fout | Rebuild gestart vóórdat de goedgekeurde diff was toegepast (log: `--docker-path podman`, oude STEP 8) | Diff toegepast 14:16; settings opnieuw kopiëren en opnieuw Rebuild |
| 2026-11-15 | Twee `--userns`-argumenten | CLI zet `--userns=keep-id` (remoteUser ≠ root), `runArgs` zette `--userns=keep-id:uid=1000,gid=1000` | `--userns` uit `runArgs` gehaald (B-07) |
| 2026-11-15 | Guard blokkeert start: `DISPLAY is gezet`, terwijl `SSH_AUTH_SOCK` leeg is | Iets voegt `DISPLAY` toe ná `env -i` in `code-agent.sh` (VS Code, Electron of shell-omgeving: TE BEVESTIGEN). Volume `vscode` was nog in gebruik door een andere dev container | Guard toont nu bij fout `DISPLAY`-waarde, `VSCODE_CLI`, ouderproces en variabelenamen (geen waarden) |
| 2026-11-15 | Diagnose guard: `DISPLAY='1'`, naast `SSH_ASKPASS`, `SSH_ASKPASS_REQUIRE`, `VSCODE_SSH_ASKPASS_*`; geen tokens, `SSH_AUTH_SOCK`, `KUBECONFIG` of shellvariabelen | Dummy-`DISPLAY` voor ssh-askpass, gezet in de extension host (niet in open-source VS Code; vermoedelijk Dev Containers-extensie, TE BEVESTIGEN). B-04 (`env -i`) werkt | Guard blokkeert alleen `DISPLAY` met `:` (echte X-display); X11 na start toetsen in log en container |
| 2026-11-15 | `BROWSER` in VS Code-terminal gezet ondanks `remoteEnv` `""` | VS Code Server injecteert eigen `browser.sh` in terminalomgeving | Geaccepteerd als restkanaal; backlog 19 |
| 2026-11-15 | Oude `check-isolation.sh` gaf altijd OK voor clustertools en miste mounts, SELinux, X11/Wayland, netwerk | Beperkte eerste versie | Herschreven (backlog 3) en in image gebakken |
| 2026-11-15 | Repo's wisselen vereiste handwerk in `devcontainer.json` | Mounts liggen vast bij aanmaken container | `select-repos.sh` + `repos.conf`/`repos.deny`, markeringen in `devcontainer.json`, `AGENT_REPOS` voor `check-isolation`; `code-agent.sh` accepteert repo-namen |
| 2026-11-15 | `check-isolation`: `FOUT verboden tools: curl` | `curl` zit in basisimage `fedora-minimal:45`; Containerfile installeerde het niet maar verwijderde het ook niet; oude check testte niet op curl | Containerfile verwijdert `curl`/`curl-minimal`/`wget`/`openssh-clients` en faalt bij elke verboden tool (B-06) |
| 2026-11-15 | Copilot toont geen modellen in de container, wel lokaal | Copilot-runtime in container: `invalid proxy TLS configuration … install libssl.so.3`; `fedora-minimal:45` heeft alleen OpenSSL 4, host heeft `openssl3-libs` | `openssl3-libs` en `ca-certificates` in Containerfile |
| 2026-11-15 | `devcontainer.json` installeert `github.copilot-chat` 0.48.1 van Marketplace | Extensie expliciet in `customizations.vscode.extensions`, terwijl stable (0.74.0) en Insiders (0.75.x) hem ingebouwd hebben | Regel verwijderd (2026-11-16) |
| 2026-11-16 | Sandbox alleen voor Insiders; oud stable-profiel `~/.config/Code-agent` had verouderde instellingen (geen wrapper, geen `cacheVolume`/`mountWaylandSocket: false`) | Paden vast in `code-agent.sh` | `edition.sh`/`edition.conf`, `setup-agent-profile.sh`; `code-agent.sh` weigert bij afwijkend profiel; B-11 gewijzigd |
| 2026-11-16 | Test `select-repos.sh <repo> --force` schreef per ongeluk die repo in de configuratie | Testfout van de agent | Direct teruggezet op de vorige keuze; geen container gestart. `--force` werkt nu op elke positie |
| 2026-11-16 | `setup-agent-profile.sh --insiders`: `Error while installing extensions: AggregateError [ETIMEDOUT]` (Fedora 45 achter http-proxy zonder authenticatie) | `env -i` wist `http(s)_proxy`; netwerk staat geen directe egress toe (curl zonder proxy: timeout, met proxy: 200). `DEP0169` is een onschuldige Node-waarschuwing | Handmatig met proxyvariabelen in `env -i`: installatie slaagt. Structureel: B-15 |
| 2026-11-16 | Rebuild blijft hangen na `Start: Resolving Remote` / `Loading … extra certificates` | Devcontainers CLI start `podman pull fedora-minimal:45` zonder proxyvariabelen (geërfd van `code-agent.sh`/`env -i`): `SYN-SENT` naar de registry. GUI zelf werkt via GNOME-proxy (Dev Containers auto-update 0.473.0 → 0.474.0) | B-15: `code-agent.sh` geeft proxyvariabelen door; end-to-end toetsen (backlog 23) |
| 2026-11-16 | Na Rebuild "terminal zonder prompt", alleen regels `Extensions cache, remote removals: None` | Het logtabblad "Dev Containers" in het terminalpaneel werd aangezien voor een shell; er was geen terminal geopend (geen `bash` onder ptyHost in `podman top`) | Nieuwe terminal openen (`+` / Ctrl+Shift+`); geen wijziging nodig |
| 2026-11-16 | Insiders-profiel wijkt af van `settings.host.json`: `"chat.viewSessions.orientation": "stacked"` toegevoegd (10:19) | VS Code schrijft UI-keuzes naar `User/settings.json` van het agentprofiel | `setup-agent-profile.sh --insiders` (maakt back-up); B-14 werkt zoals bedoeld |
| 2026-11-16 | `restorecon -R ~/git` veranderde niets (geen melding); de dry-run met `-v` telde wel 52.384 regels | `container_file_t` is een *customizable type* (`customizable_types`); restorecon zet zulke labels alleen terug met `-F` | `restorecon -RF ~/git` (backlog 6) |
| 2026-11-16 | Eerste versie `render_settings` (awk) gaf een ander profiel dan `cp` | `settings.host.json` eindigt zonder regeleinde; awk voegt er een toe | GNU `sed`, laat het ontbrekende regeleinde intact; stable-profiel byte voor byte gelijk |
| 2026-11-16 | HEAD `11b70ce` (gepusht naar de publieke repo) bevat eigen repo-namen in `repos.conf`, `devcontainer.json` en `tst.code-workspace` | Commit zonder `select-repos.sh --stage-example`; de werkkopie met de eigen keuze is meegecommit | `.githooks/pre-commit` weigert zulke commits, `.gitignore` voor `repo-root.conf`; fix-commit door gebruiker |
