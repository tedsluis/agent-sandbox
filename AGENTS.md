# AGENTS.md – agent-sandbox

Deze repo bevat de configuratie van een geïsoleerde Dev Container voor AI-agents. Je werkt hier op de **host**, niet in de sandbox: fouten hier kunnen de isolatie breken. Lees eerst `PROJECT.md` (doel, besluiten B-01…B-14, status, backlog) en `ARCHITECTURE.md` (ontwerp, isolatielagen, dreigingsmodel). `README.md` is de gebruikershandleiding.

## Wat je nooit doet

- Geen secrets lezen, tonen of gebruiken: niet `~/.ssh`, `~/.kube`, `~/.bashrc`, `~/.gnupg`, `~/.config/containers`, `~/.local/share/keyrings`, `~/.git-credentials`, omgevingsvariabelen met tokens.
- Geen `ssh`, `scp`, `oc`, `kubectl`, `helm install/upgrade`, `ansible*`, `vault`, `kubeseal`, `sudo`, `git push`, `git commit`.
- Geen podman-commando's die iets wijzigen (`build`, `run`, `rm`, `volume rm`, `system prune`, `restorecon`, `chcon`). Stel ze voor in chat; de gebruiker voert ze uit en plakt de output.
- Niets toevoegen dat een besluit in `PROJECT.md` terugdraait zonder expliciet akkoord. In het bijzonder:
  - geen mount van `$HOME`, `~/git` als geheel, `~/.kube`, `~/.ssh` of de podman-/docker-socket;
  - geen `--privileged`, extra capabilities, `label=disable`, `--network=host`;
  - geen `DISPLAY`/X11 of Wayland-socket naar de container;
  - geen tools in de eindimage die credentials of clustertoegang gebruiken (ssh, oc, kubectl, helm, ansible, curl, wget); de build-check in de Containerfile niet verzwakken;
  - `.devcontainer/` en de rest van `~/agent-sandbox` blijven buiten de container-mounts;
  - `podman-agent.sh` (SELinux), `guard-host-env.sh` en de profielcontrole in `code-agent.sh` niet omzeilen of verzwakken.
- Geen bestanden buiten `~/agent-sandbox` wijzigen. `setup-agent-profile.sh` schrijft in de agentprofielen buiten deze map: alleen de gebruiker draait dat.
- `select-repos.sh` alleen draaien op verzoek van de gebruiker en nooit met `--force`: het schrijft `devcontainer.json`, `tst.code-workspace` en `repos.conf`. Weigertests mogen; een test die slaagt, verandert de configuratie. Het blok `// BEGIN repos … // END repos` niet met de hand aanpassen.

## Wat je wel mag

- Bestanden in deze repo lezen en wijzigen, na een voorgestelde diff.
- Lezend: `cat`, `grep`, `find`, `diff`, `jq`, `bash -n`, `git status/diff/log`, `kustomize build` `podman images`, `podman ps -a`, `podman inspect`, `podman volume ls`, `code --list-extensions`, `code-insiders --list-extensions`, `yamllint` met de agentprofiel-directories.
- JSON(C) valideren (commentaar `//` toegestaan in `devcontainer.json` en `settings.host.json`).

## Werkwijze

1. Bij elke wijziging: noem de laag uit `ARCHITECTURE.md` §3 die je raakt en of het dreigingsmodel (§6) verandert.
2. Feiten over VS Code, Dev Containers, podman of Copilot (instellingsnamen, flags) verifieer je in de officiële documentatie of in logs; markeer onbevestigde namen als `TE BEVESTIGEN`.
3. Elke wijziging krijgt een testregel: welk podman-commando of welke logregel bewijst dat het werkt. Breid zo nodig `.devcontainer/check-isolation.sh` uit (in de container: `check-isolation`).
4. Werk na afloop `PROJECT.md` (status, logboek, backlog) en zo nodig `ARCHITECTURE.md` bij.
5. Meld in chat: gewijzigde bestanden, wat de gebruiker moet uitvoeren (Rebuild, `setup-agent-profile.sh --stable|--insiders` na wijziging van `settings.host.json`) en wat nog getest moet worden.
6. Houd `README.md` bij als gebruik of commando's veranderen.