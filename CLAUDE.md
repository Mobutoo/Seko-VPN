# CLAUDE.md — Instructions pour Claude Code

## Identite du Projet

Ce repository est un projet **Ansible** (V3) qui deploie automatiquement une infrastructure VPN + services self-hosted complete sur un VPS Debian unique avec Docker Compose. L'approche est **"fire-and-forget"** : une fois deploye, le serveur se maintient seul (mises a jour de securite, rotation des logs, monitoring, alertes Telegram, auto-remediation).

Le projet est concu comme un **template portable** : toutes les valeurs sont des variables Jinja2 configurees via un wizard interactif (`scripts/wizard.sh`). Aucun nom de serveur ou domaine n'est hardcode.

## Acces GitHub

- **Repository** : `Mobutoo/Seko-VPN` (prive)
- **Remote** : `git@github-seko:Mobutoo/Seko-VPN.git`
- **Host SSH** : `github-seko` (configure dans `~/.ssh/config`, utilise la cle `~/.ssh/id_ed25519_seko`)
- **Branche principale** : `main`
- **Compte GitHub** : Mobutoo

> **Important** : Toujours utiliser `github-seko` comme host dans les commandes git, jamais `github.com` directement. C'est un alias SSH pour le bon couple cle/compte.

## Documents de Reference

**Lire OBLIGATOIREMENT avant de coder :**

1. `docs/01-architecture.md` — Architecture complete : services, reseau, monitoring, hardening
2. `docs/02-guide-deploiement.md` — Guide de deploiement pas a pas
3. `docs/03-gitops.md` — Workflow GitOps et CI/CD
4. `docs/04-roles-reference.md` — Reference detaillee des 14 roles Ansible
5. `docs/05-troubleshooting.md` — Depannage et pieges connus (Phases 1-5)
6. `docs/06-v4-roadmap.md` — Feuille de route V4 (hors perimetre V3)
7. `docs/07-rex-v3.1.md` — REX post-deploiement production (DERP, Headplane, CI/CD)

## Stack Technique

- **Orchestration** : Ansible 2.16+ (collections community.docker >=5.0, community.general >=9.0, ansible.posix >=1.5)
- **Conteneurisation** : Docker CE + Docker Compose V2 (plugin)
- **Reverse Proxy** : Caddy (TLS auto Let's Encrypt, HSTS, HTTP/2)
- **VPN** : Headscale 0.26.0 (serveur WireGuard) + Headplane (UI web)
- **Mots de passe** : Vaultwarden 1.35.1-alpine (compatible Bitwarden)
- **Gestion Docker** : Portainer CE (LTS)
- **Sauvegardes** : Zerobyte v0.26.0
- **Monitoring HTTP** : Uptime Kuma
- **Watchdog** : Monit (headless, alertes Telegram uniquement)
- **Collecteur logs** : Grafana Alloy (pret pour Loki en V4)
- **Bot** : Telegram Bot Python interactif (/status, /restart, /logs, /disk)
- **Systeme** : Fail2Ban, UFW, chrony NTP, unattended-upgrades, swap, sysctl hardening
- **CI/CD** : GitHub Actions (lint -> Molecule 14 roles -> integration Hetzner -> deploy IONOS)
- **OS cible** : Debian 13 (teste en CI), Debian 12 compatible
- **Python** : 3.12 (CI), 3.11+ (dev local)

## Conventions et Regles Strictes

### Ansible

- **FQCN obligatoire** pour tous les modules : `ansible.builtin.apt`, `ansible.builtin.file`, `community.docker.docker_compose_v2`, etc. Jamais `apt` ou `file` seul
- **`changed_when` / `failed_when`** explicites sur toutes les taches `command` et `shell`
- **Pas de `command`/`shell`** si un module Ansible existe pour la tache
- **Idempotence** : chaque role doit pouvoir s'executer 2 fois consecutives avec 0 changed a la 2eme
- **Variables** : toujours dans `defaults/main.yml` (overridable). Les variables sont centralisees dans `inventory/group_vars/all/vars.yml`
- **Secrets** : dans `inventory/group_vars/all/vault.yml` (chiffre avec Ansible Vault)
- **Handlers** : utiliser `notify` + handler pour tout restart de service
- **Tags** : chaque role a un tag correspondant a son nom (ex: `tags: [headscale]`, `tags: [caddy]`)
- **`become: true`** est defini globalement dans `ansible.cfg` (privilege_escalation), pas besoin de le repeter par tache
- **Profil ansible-lint** : `production` (le plus strict)
- **Skips ansible-lint** : `var-naming[no-role-prefix]` et `command-instead-of-module` (volontaires)

### Docker

- **Reseau unique `proxy-net`** : tous les conteneurs partagent un seul reseau Docker bridge. Seul Caddy expose les ports 80/443 vers l'exterieur
- **`community.docker.docker_compose_v2`** pour gerer les stacks (pas de `docker_container` individuel)
- **Images pinnees** dans `inventory/group_vars/all/vars.yml` : `headscale_version`, `vaultwarden_version`, etc.
- **Exception** : `headplane_version: "latest"` et `uptime_kuma_version: "latest"` (images sans tags stables)
- **Deploiement** : chaque service a son `docker-compose.yml.j2` dans `roles/<service>/templates/`
- **Chemin de base** : `{{ base_deploy_path }}` (defaut `/opt/services`) — tous les services deployent sous ce chemin

### Templates Jinja2

- **Toute valeur configurable** utilise une variable du wizard : `{{ domain_headscale }}`, `{{ server_ip }}`, etc.
- **Extension `.j2`** pour tous les templates
- **ci_mode** : variable booleenne qui adapte le comportement en CI (certificats locaux, domaines fictifs)

### Securite

- **SSH** : port custom (`ssh_custom_port: 804`), cle publique Ed25519 uniquement
- **Secrets** : tous dans `inventory/group_vars/all/vault.yml` chiffre avec Ansible Vault
- **Jamais de secret en clair** dans les fichiers YAML, templates, ou scripts
- **Ports ouverts (UFW)** : 22 (ou custom), 80 (redirect HTTPS), 443 (TLS), 41641/UDP (WireGuard), 3478/UDP (STUN/DERP embarque Headscale)
- **Fail2Ban** surveille les tentatives SSH
- **Contraintes critiques sur les secrets** :
  - `vault_monit_password` : alphanumerique UNIQUEMENT (pas de `"`, `#`, `{`, `}`), sinon Monit refuse de demarrer
  - `vault_zerobyte_app_secret` : exactement 64 caracteres hexadecimaux, sinon le conteneur crash
  - `vault_headplane_cookie_secret` : exactement 32 caracteres, sinon l'authentification echoue

### Documentation

- Chaque role a un repertoire `molecule/default/` avec `molecule.yml`, `converge.yml` et `verify.yml`
- Documentation operationnelle dans `docs/` (7 fichiers)

## Structure du Repository

```
Seko-VPN/
├── .github/workflows/
│   └── ci-cd.yml                # Pipeline CI/CD (4 stages)
├── inventory/
│   ├── hosts.yml                # Inventaire (IP du VPS cible)
│   └── group_vars/all/
│       ├── vars.yml             # Variables publiques (genere par wizard.sh)
│       └── vault.yml            # Secrets (chiffre Ansible Vault)
├── roles/                       # 14 roles Ansible (dans l'ordre d'execution)
│   ├── common/                  # 1. Utilisateur systeme, paquets, locale
│   ├── security/                # 2. UFW, Fail2Ban, sysctl
│   ├── docker/                  # 3. Docker Engine + Compose + reseau proxy-net
│   ├── hardening/               # 4. journald, logrotate, chrony, swap, unattended-upgrades
│   ├── caddy/                   # 5. Reverse proxy (6 vhosts, SSL auto)
│   ├── headscale/               # 6. Serveur VPN WireGuard
│   ├── headplane/               # 7. UI web VPN
│   ├── vaultwarden/             # 8. Gestionnaire de mots de passe
│   ├── portainer/               # 9. UI Docker
│   ├── zerobyte/                # 10. Sauvegardes chiffrees
│   ├── uptime_kuma/             # 11. Monitoring HTTP/TCP/DNS
│   ├── monit/                   # 12. Watchdog headless (alertes Telegram)
│   ├── alloy/                   # 13. Collecteur de logs (Grafana Alloy)
│   └── telegram_bot/            # 14. Bot Telegram interactif
│   └── <chaque role>/
│       ├── tasks/main.yml
│       ├── defaults/main.yml
│       ├── handlers/main.yml    # (si applicable)
│       ├── templates/           # Templates Jinja2 (.j2)
│       └── molecule/default/
│           ├── molecule.yml
│           ├── converge.yml
│           └── verify.yml
├── playbooks/
│   ├── site.yml                 # Deploie les 14 roles dans l'ordre
│   ├── verify.yml               # Verification automatisee post-deploiement
│   ├── harden-ssh.yml           # Hardening SSH (post-validation)
│   ├── verify-ssh-hardening.yml # Verification du hardening SSH
│   ├── set-hostname.yml         # Changer le hostname
│   └── wsl-repair.yml           # Repare DNS/systemd WSL2
├── scripts/
│   ├── wizard.sh                # Configuration interactive (genere vars.yml + vault.yml)
│   ├── bootstrap-vps.sh         # Preparation VPS (user + SSH + sudo)
│   ├── bootstrap-ionos.sh       # Preparation specifique IONOS
│   ├── setup-ci.sh              # Installation env CI local
│   ├── fix-lint.sh              # Correction auto violations lint
│   └── hetzner-ci-server.sh     # Gestion VM Hetzner ephemere
├── templates/                   # Templates partages pour wizard.sh
│   ├── vars.yml.j2
│   └── vault.yml.j2
├── tests/
│   └── ci-vars.yml              # Variables CI (ci_mode: true, domaines fictifs)
├── docs/                        # Documentation operationnelle (7 fichiers)
├── ansible.cfg                  # Config Ansible (inventaire, roles, SSH)
├── requirements.yml             # Collections Ansible requises
├── requirements-dev.txt         # Dependances dev (Molecule, ansible-lint, yamllint)
├── Makefile                     # Commandes make (lint, molecule, wizard, clean)
├── .yamllint                    # Config yamllint
├── .ansible-lint                # Config ansible-lint (profil production)
└── .gitignore
```

## Commandes Utiles

```bash
# Environnement de developpement
make venv                                          # Creer le venv + installer dependances
source .venv/bin/activate                          # Activer le venv

# Linting
make lint                                          # yamllint + ansible-lint

# Tests Molecule
make molecule                                      # Tester tous les 14 roles
make role ROLE=headscale                           # Tester un role specifique

# Deploiement
ansible-playbook playbooks/site.yml --ask-vault-pass                    # Deploiement complet
ansible-playbook playbooks/site.yml --tags caddy --ask-vault-pass       # Un seul role
ansible-playbook playbooks/site.yml --check --diff --ask-vault-pass     # Dry run

# Verification
ansible-playbook playbooks/verify.yml --ask-vault-pass                  # Verification post-deploy

# Vault
ansible-vault edit inventory/group_vars/all/vault.yml
ansible-vault encrypt_string 'my_secret' --name 'variable_name'

# Nettoyage
make clean                                         # Detruire les conteneurs Molecule orphelins

# Configuration
make wizard                                        # Lancer le wizard interactif

# WSL
make wsl-repair                                    # Corriger DNS/systemd WSL2
```

## Pipeline CI/CD (4 stages)

Le pipeline `.github/workflows/ci-cd.yml` s'execute sur push `main`/`develop` et PR vers `main` :

1. **Lint** : yamllint + ansible-lint
2. **Molecule** : Tests unitaires des 14 roles en parallele (matrice `fail-fast: false`)
3. **Integration** : VM ephemere Hetzner (Debian 13), execution complete de `site.yml` + `verify.yml`, puis destruction automatique
4. **Deploy** : Deploiement en production sur IONOS (uniquement push main, approbation manuelle via environment `production`)

### Secrets GitHub Actions requis

| Secret | Usage |
|--------|-------|
| `HCLOUD_TOKEN` | Creer/detruire les VM ephemeres Hetzner (stage 3) |
| `DEPLOY_SSH_KEY` | Connexion SSH au VPS production (stage 4) |
| `VAULT_PASSWORD` | Dechiffrer vault.yml pendant le deploy (stage 4) |

## Ordre d'Execution des Roles

Les 14 roles s'executent dans un ordre precis (defini dans `playbooks/site.yml`). L'ordre est critique car chaque role depend des precedents :

```
 1. common          -> Utilisateur systeme, paquets de base, locale
 2. security        -> UFW, Fail2Ban, sysctl securite
 3. docker          -> Docker Engine, Compose, reseau proxy-net
 4. hardening       -> journald, logrotate, chrony, swap, unattended-upgrades
 5. caddy           -> Reverse proxy avec 6 vhosts + SSL auto
 6. headscale       -> Serveur VPN WireGuard
 7. headplane       -> Interface web VPN (distroless)
 8. vaultwarden     -> Gestionnaire de mots de passe
 9. portainer       -> Interface Docker
10. zerobyte        -> Sauvegardes chiffrees
11. uptime_kuma     -> Monitoring HTTP
12. monit           -> Watchdog systeme (surveille TOUS les services ci-dessus)
13. alloy           -> Collecteur de logs
14. telegram_bot    -> Bot Telegram interactif
```

> Les roles infrastructure (1-4) doivent etre prets AVANT les services applicatifs (5-11). Monit (12) vient APRES car il surveille tous les services. Le bot Telegram (14) vient en dernier car il utilise Monit pour `/status`.

## Architecture Reseau

```
Client HTTPS --> Caddy :443 --> Conteneur backend (port interne)
                    |
                    |-- singa.*.cloud    -> headscale:8080 (API + DERP embarque)
                    |-- seko.*.cloud     -> headplane:3000
                    |-- fongola.*.cloud  -> vaultwarden:80
                    |-- pao.*.cloud      -> portainer:9000
                    |-- buku.*.cloud     -> zerobyte:4096
                    +-- misu.*.cloud     -> uptime-kuma:3001

STUN :3478/UDP -----> headscale (DERP embarque)
WireGuard :41641/UDP -> headscale

Magic DNS interne : *.na.ewutelo.cloud (resolution VPN uniquement)
```

- Un seul reseau Docker bridge : `proxy-net`
- Caddy expose les ports 80/443, Headscale expose 3478/UDP (STUN)
- Monit est **headless** : pas de vhost, acces uniquement en SSH (`sudo monit status`)
- **DERP embarque** : le serveur Headscale fait office de relais DERP, zero trafic via Tailscale Inc
- **Deux domaines Headscale** : `domain_headscale` (API publique) ≠ `headscale_base_domain` (Magic DNS interne)

## Monitoring (4 couches)

| Outil | Detection | Auto-fix | Dashboard web | Interactif |
|-------|-----------|----------|---------------|------------|
| **Monit** | Processus, CPU, RAM, disque | Restart auto | Non (headless) | Non |
| **Uptime Kuma** | Endpoints HTTPS, TCP, DNS | Non | Oui (status.*) | Non |
| **Grafana Alloy** | Collecte logs Docker/journald | Non | Non | Non |
| **Telegram Bot** | Sur demande (/status) | /restart (avec confirm) | Non | Oui |

## Pieges Connus et Regles de Qualite (REX)

### Encodage et Fins de Ligne

- **TOUS les fichiers YAML/Jinja2 doivent etre en UTF-8 avec fins de ligne LF (Unix)**
- **Jamais de CRLF (Windows)** : yamllint echoue avec `wrong new line character: expected \n`
- **Attention au tiret long** : `--` (em dash, U+2014) en Windows-1252 est le byte `0x97` qui casse le parsing UTF-8
- **Fix si besoin** : `find roles/ -name '*.yml' -exec sed -i 's/\r$//' {} \;`

### ansible-lint

- **Profil** : `production` (le plus strict)
- **`name[template]`** : Les templates Jinja2 dans le champ `name:` doivent etre **a la fin** de la chaine
  - Mauvais : `- name: "Deploy {{ project_name }} -- Full Stack"`
  - Bon : `- name: "Deploy Full Stack -- {{ project_display_name }}"`
- **`schema[meta]`** : Le `role_name` dans `meta/main.yml` doit correspondre au pattern `^[a-z][a-z0-9_]+$` (pas de tirets)
- **`offline: true`** : Obligatoire dans `.ansible-lint` si pas de Galaxy configure

### yamllint

- **`octal-values`** : `forbid-implicit-octal: true` et `forbid-explicit-octal: true` (requis par ansible-lint)
- **`vault.yml`** : dans le `ignore:` de `.yamllint` (fichier chiffre)
- **`document-start: present: true`** : le `---` est obligatoire en debut de chaque fichier YAML
- **Indentation** : 2 espaces, `indent-sequences: true`
- **Longueur de ligne** : max 200 (warning, pas erreur)

### Molecule

- **Driver** : Docker (`geerlingguy/docker-debian12-ansible`)
- **Mode privilegie** : `privileged: true` + `cgroupns_mode: host` (requis pour systemd dans Docker)
- **Verifier** : Ansible (pas Testinfra)
- **`ANSIBLE_ROLES_PATH`** : `../../../../roles` (pour les dependances inter-roles)
- **Headplane** : skip idempotence en CI (container crash-loop normal)
- **Piège `creates:` + `changed_when: true`** : echec idempotence au 2e run (tache skippee mais marquee changed)
  → Fix : `changed_when: _var.stdout is not search('skipped')` pour detecter si la tache a vraiment tourne
- **Nouvelle variable dans un template** : toujours ajouter dans `defaults/main.yml` ET `molecule/default/converge.yml`

### Secrets — Contraintes critiques

| Secret | Contrainte | Si non respecte |
|--------|-----------|-----------------|
| `vault_monit_password` | Alphanumerique uniquement (pas de `"#{}`) | Monit refuse de demarrer |
| `vault_zerobyte_app_secret` | Exactement 64 chars hexadecimaux | Conteneur crash au demarrage |
| `vault_headplane_cookie_secret` | Exactement 32 caracteres | Authentification echoue |
| `vault_vaultwarden_admin_token` | Base64, 32 chars | UI admin inaccessible |
| `uptime_kuma_admin_username` | **Sensible a la casse** (`admin` ≠ `Admin`) | Monitors non crees (skip silencieux) |

### Headscale extra_records — Pièges critiques

- **`server_tailscale_ip`** = IP publique IONOS (`87.106.30.160`), **pas** `100.64.x.x` — le VPS n'est pas client de lui-meme
- **Bootstrap DNS circulaire** : si un noeud resout `singa.ewutelo.cloud` → sa propre IP (cache Tailscale corrompu),
  il ne peut plus rejoindre Headscale → fix temporaire : `echo "87.106.30.160 singa.ewutelo.cloud" | sudo tee -a /etc/hosts`
  puis `sudo systemctl restart tailscaled` (supprimer l'entree /etc/hosts apres reconnexion)
- **Apres `docker restart headscale`** : toujours redemarrer Headplane (`sudo docker restart headplane`)
- **Diagnostiquer depuis un noeud** : `curl -v https://singa.ewutelo.cloud/health` — doit retourner `{"status":"pass"}`

### Pipeline CI — Comportement multi-commits

- **Commits rapides groupes** : GitHub Actions peut ne lancer qu'un seul pipeline pour plusieurs commits pushes
  rapidement → si le pipeline echoue sur un commit intermediaire, forcer un nouveau run :
  `git commit --allow-empty -m 'ci: relancer le pipeline'`
- **Pas de `workflow_dispatch`** : impossible de relancer manuellement sans nouveau commit
- **Deploy (stage 4)** : attend une approbation manuelle via environment `production` sur GitHub Actions UI

### Grafana Alloy

- **Format HCL** (HashiCorp Configuration Language), pas YAML
- **Variable `alloy_loki_url`** : vide par defaut, a configurer quand un serveur Loki sera disponible (V4)

### Environnement de Developpement (WSL)

- **venv Python** : `.venv/` (dans `.gitignore`)
- **Activer le venv** avant toute commande : `source .venv/bin/activate`
- **Safe directory Git** : si erreur `dubious ownership`, executer :
  ```bash
  git config --global --add safe.directory '%(prefix)///wsl.localhost/Ubuntu/home/asus/seko/VPN/Seko-VPN'
  ```
- **WSL repair** : `make wsl-repair` corrige les problemes DNS/systemd courants

## Infrastructure Multi-Serveurs (Réseau Headscale)

Seko-VPN est le **coordinateur central** d'un réseau Tailscale multi-nœuds :

| Nœud | IP publique | IP Tailscale | Role |
|------|-------------|--------------|------|
| `vps` (IONOS) | `87.106.30.160` | N/A (coordinateur) | Seko-VPN (14 roles) |
| `sese` (Javisi) | `137.74.114.167` | `100.64.0.14` | VPAI (n8n, LiteLLM, Grafana, Qdrant…) |
| `ewutelo` (Windows) | — | `100.64.0.2` | Machine de developpement |

- **`server_tailscale_ip`** dans `vars.yml` = IP **publique** IONOS (`87.106.30.160`), **pas** une IP `100.64.x.x`
  → Le VPS coordinateur Headscale n'est pas client de lui-meme
- **Domaines des autres noeuds** : variable `nodes_extra_records` dans `vars.yml` — liste declarative avec `tailscale_ip` et `domains`
- **Ajouter un noeud** : ajouter une entree `nodes_extra_records` + redéployer `--tags headscale`
- **Verifier la propagation DNS** : `powershell.exe -Command "Resolve-DnsName qd.ewutelo.cloud"`
  → doit retourner l'IP Tailscale du noeud (ex: `100.64.0.14`), pas l'IP publique OVH

## Acces SSH au VPS

- **Cle SSH** : `/home/asus/.ssh/seko-vpn-deploy` (WSL) — **pas** `id_ed25519_seko`
- **User** : `mobuone`
- **Port** : `22` (avant hardening SSH) ou `804` (apres hardening SSH actif)
- **Via WSL** : `ssh -i /home/asus/.ssh/seko-vpn-deploy -p 22 mobuone@87.106.30.160`
- **Via PowerShell** : `ssh -i '\\wsl.localhost\Ubuntu\home\asus\.ssh\seko-vpn-deploy' -p 22 mobuone@87.106.30.160`
- **Tailscale** : WSL n'a **pas** acces au daemon Tailscale Windows → utiliser PowerShell pour SSH via `100.64.x.x`
- **Test port** : `powershell.exe -Command "Test-NetConnection -ComputerName 87.106.30.160 -Port 804 | Select TcpTestSucceeded"`
- **Tailscale status** : `powershell.exe -Command "tailscale status"` (depuis WSL uniquement via PowerShell)

## Feuille de Route V4

Les priorites pour la V4 (hors perimetre V3) :

1. **SSO/OIDC centralise** (Authelia) — Haute priorite
2. **Backup chiffre vers S3** (Backblaze B2 / Wasabi) — Haute priorite
3. **Multi-serveur Telegram Bot** (architecture agent/central via Headscale VPN) — Haute priorite
3b. **Security Hardening V3.2** (9 axes : cap_drop, Fail2Ban HTTP, ACL, segmentation reseau, SSH VPN-only) — Haute priorite
4. Scanning de vulnerabilites (Trivy dans CI) — Moyenne priorite
5. Support multi-OS (Ubuntu, Rocky Linux) — Moyenne priorite
6. Stack observabilite complete (Loki + Prometheus + Grafana) — Moyenne priorite

Voir `docs/06-v4-roadmap.md` pour les details.
