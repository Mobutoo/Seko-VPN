# 📦 Référence des 14 rôles Ansible

> Chaque rôle est décrit avec : son objectif, ses variables, ses templates, ses particularités et ses tests Molecule. Utile pour les contributeurs qui veulent modifier un rôle.

---

## Vue d'ensemble

| # | Rôle | Type | Catégorie | Ce qu'il fait |
|---|------|------|-----------|---------------|
| 1 | `common` | Base | Infrastructure | Utilisateur système, paquets de base, locale |
| 2 | `security` | Base | Infrastructure | UFW, Fail2Ban, sysctl sécurité |
| 3 | `docker` | DinD | Infrastructure | Docker Engine 29 + Compose v5 + réseau proxy-net |
| 4 | `hardening` | Systemd | Infrastructure | journald, logrotate, chrony, swap, unattended-upgrades |
| 5 | `caddy` | Conteneur | Reverse proxy | 6 vhosts, SSL auto, support ci_mode |
| 6 | `headscale` | Conteneur | Service | Serveur VPN WireGuard |
| 7 | `headplane` | Conteneur | Service | Interface admin VPN (image distroless) |
| 8 | `vaultwarden` | Conteneur | Service | Gestionnaire de mots de passe |
| 9 | `portainer` | Conteneur | Service | Interface Docker |
| 10 | `zerobyte` | Conteneur | Service | Sauvegardes chiffrées |
| 11 | `uptime_kuma` | Conteneur | Monitoring | Monitoring HTTP/TCP/DNS avec dashboard |
| 12 | `monit` | Systemd | Monitoring | Watchdog HEADLESS + alertes Telegram |
| 13 | `alloy` | Systemd | Monitoring | Collecteur logs (Grafana Alloy) |
| 14 | `telegram_bot` | Systemd | Monitoring | Bot interactif Python |

---

## Structure standard d'un rôle

Chaque rôle suit la même organisation :

```
roles/<nom>/
├── tasks/main.yml           # Tâches Ansible (le code principal)
├── handlers/main.yml        # Actions déclenchées par notify (restart, reload)
├── templates/               # Fichiers Jinja2 (.j2) rendus sur le serveur
├── defaults/main.yml        # Variables par défaut (écrasables)
├── molecule/default/
│   ├── molecule.yml         # Configuration Molecule (image, prérequis)
│   ├── converge.yml         # Playbook de test (exécute le rôle avec vars mock)
│   ├── prepare.yml          # Prérequis (optionnel — Docker pour les conteneurs)
│   └── verify.yml           # Vérifications post-exécution
```

---

## Rôle 1 : common

**Objectif :** Créer l'utilisateur système, installer les paquets de base, configurer la locale.

| Variable | Défaut | Description |
|----------|--------|-------------|
| `system_user` | `srvadmin` | Nom de l'utilisateur système |
| `system_user_ssh_pubkey` | — | Clé SSH publique |

**Tâches principales :** création de l'utilisateur, ajout au groupe sudo, installation des paquets essentiels (`curl`, `wget`, `htop`, `vim`, `gnupg`, etc.), configuration de la locale `fr_FR.UTF-8`.

---

## Rôle 2 : security

**Objectif :** Configurer le firewall (UFW), Fail2Ban et les paramètres sysctl de sécurité.

| Variable | Défaut | Description |
|----------|--------|-------------|
| `ssh_custom_port` | `804` | Port SSH personnalisé |

**Tâches principales :** activation UFW, règles allow (SSH, HTTP, HTTPS, WireGuard), installation Fail2Ban, configuration sysctl (`net.ipv4.ip_forward`, `net.ipv4.conf.all.rp_filter`, etc.).

---

## Rôle 3 : docker

**Objectif :** Installer Docker Engine 29+ depuis le dépôt officiel Docker, le plugin Compose v5, et créer le réseau `proxy-net`.

> **⚠️ IMPORTANT :** Ce rôle utilise le dépôt `download.docker.com`, PAS le paquet `docker.io` des dépôts Debian. C'est obligatoire pour avoir Docker Engine 29+ avec le plugin Compose v5.

**Tâches principales :** ajout du dépôt Docker, installation `docker-ce`, `docker-ce-cli`, `docker-compose-plugin`, configuration `daemon.json` (log rotation), création du réseau bridge `proxy-net`, ajout de l'utilisateur au groupe `docker`.

**Vérification Molecule :** `docker version` + `docker compose version` + existence du réseau `proxy-net`.

---

## Rôle 4 : hardening

**Objectif :** Configurer le serveur pour la production long terme.

| Variable | Défaut | Description |
|----------|--------|-------------|
| `hardening_swap_size` | `2G` | Taille du swap (si RAM < 4 Go) |
| `hardening_journal_max_use` | `500M` | Limite taille journald |
| `hardening_journal_max_retention` | `30day` | Rétention des journaux |

**Composants :**

| Composant | Template | Service |
|-----------|----------|---------|
| journald | `journald.conf.j2` | `systemd-journald` |
| logrotate | `logrotate-*.j2` | — |
| chrony | — (installation apt) | `chronyd` |
| swap | — (conditionnel si RAM < 4 Go) | fstab |
| unattended-upgrades | `50unattended-upgrades.j2`, `20auto-upgrades.j2` | `unattended-upgrades` |
| docker-prune | `docker-prune.service.j2`, `docker-prune.timer.j2` | Timer hebdomadaire |
| sysctl | — | `kernel.panic=10`, `fs.file-max=2097152` |
| Docker LimitNOFILE | `docker-override.conf.j2` | Override systemd Docker |

---

## Rôle 5 : caddy

**Objectif :** Déployer Caddy comme reverse proxy avec 6 vhosts et SSL automatique.

**Template principal :** `Caddyfile.j2` — contient les 6 vhosts + le bloc conditionnel `ci_mode`.

**Particularité ci_mode :**

```jinja2
{% if ci_mode | default(false) %}
{
    local_certs
    skip_install_trust
}
{% endif %}
```

> **⚠️ Piège Headplane :** Le vhost Headplane DOIT avoir `redir / /admin permanent`. Headplane attend que TOUTES les requêtes arrivent avec le préfixe `/admin` (c'est hardcodé dans l'image). Il faut un sous-domaine dédié.

**Molecule :** Nécessite `prepare.yml` (Docker + proxy-net).

---

## Rôle 7 : headplane

**Objectif :** Déployer l'interface web de gestion Headscale.

> **⚠️ Contraintes critiques (image distroless) :**
>
> - **Pas de healthcheck Docker** — L'image distroless ne contient ni `wget`, ni `curl`, ni `sh`. Le healthcheck est impossible.
> - **Sous-domaine dédié obligatoire** — Pas de `handle_path /admin*` (casse les assets). Utiliser `redir / /admin permanent`.
> - **COOKIE_SECRET exactement 32 chars** — Sinon l'auth échoue silencieusement.

---

## Rôle 10 : zerobyte

**Objectif :** Déployer le service de sauvegardes chiffrées.

> **⚠️ Contrainte critique :** `APP_SECRET` doit faire exactement 64 caractères hexadécimaux. Le wizard.sh le génère avec `openssl rand -hex 32` (qui produit 64 hex chars). Si cette variable est manquante ou mal formatée, le conteneur refuse de démarrer.

---

## Rôle 12 : monit

**Objectif :** Installer Monit en mode HEADLESS comme watchdog système.

**Mode HEADLESS V3 :** Le template `monitrc.j2` contient `allow localhost` uniquement. PAS de `allow 172.x.x.x`, PAS de vhost Caddy.

| Template | Description |
|----------|-------------|
| `monitrc.j2` | Configuration principale (httpd localhost, alertes) |
| `conf.d/system.j2` | Check CPU, RAM, disque, swap |
| `conf.d/docker-daemon.j2` | Check service Docker |
| `conf.d/docker-containers.j2` | Check des 7 conteneurs (+ uptime-kuma) |
| `conf.d/alloy.j2` | Check process alloy |
| `conf.d/telegram-bot.j2` | Check process telegram-bot |
| `telegram-alert.sh.j2` | Script d'alerte Telegram |

> **⚠️ Pièges Monit :**
>
> - Le mot de passe ne doit contenir QUE des lettres et chiffres (`a-zA-Z0-9`). Les caractères `"`, `#`, `{`, `}` cassent le parser Monit.
> - La directive `exec` ne peut apparaître que dans les blocs `check`, JAMAIS dans `set alert`.
> - Toujours vérifier avec `monit -t` (test syntaxe) dans le `verify.yml`.

---

## Rôle 13 : alloy

**Objectif :** Installer Grafana Alloy comme collecteur de logs.

**Installation :** Via apt (dépôt Grafana officiel), PAS Docker.

> **⚠️ Piège `gpg --dearmor` :** Lors de l'ajout du dépôt Grafana, la commande DOIT utiliser `gpg --yes --dearmor` (avec `--yes`). Sans `--yes`, la commande attend un prompt interactif et bloque Ansible.

**Template :** `config.alloy.j2` — collecte Docker logs + journald. L'endpoint Loki est commenté, prêt à être activé en V4.

---

## Rôle 14 : telegram_bot

**Objectif :** Déployer le bot Telegram interactif comme service systemd.

| Template | Description |
|----------|-------------|
| `bot.py.j2` | Script Python principal (commandes /status, /restart, etc.) |
| `.env.j2` | Variables d'environnement (token, chat IDs) — **mode 600** |
| `requirements.txt.j2` | Dépendance `python-telegram-bot` |
| `telegram-bot.service.j2` | Unité systemd |

**Sécurité :** Le fichier `.env` est en mode `600` (lisible uniquement par root). Le bot vérifie `ALLOWED_CHAT_IDS` et ignore les messages des autres utilisateurs. La commande `/restart` demande une confirmation.

**Multi-serveur (préparé pour V4) :** Chaque réponse est préfixée par `[nom-du-serveur]` (variable `telegram_bot_server_name`).

---

## Molecule — Résumé des tests par rôle

| Rôle | Vérifications clés dans `verify.yml` |
|------|--------------------------------------|
| common | Utilisateur existe, sudo configuré, paquets installés |
| security | UFW actif, Fail2Ban actif, sysctl configuré |
| docker | `docker version`, `docker compose version`, réseau proxy-net |
| hardening | journald.conf, chrony actif, logrotate configs, swap, unattended-upgrades, docker-prune.timer |
| caddy | Conteneur running, Caddyfile (6 vhosts), proxy-net |
| headscale | Conteneur running, config.yaml, proxy-net |
| headplane | Conteneur running, proxy-net (PAS de healthcheck) |
| vaultwarden | Conteneur running, proxy-net |
| portainer | Conteneur running, proxy-net |
| zerobyte | Conteneur running, proxy-net |
| uptime_kuma | Conteneur running, proxy-net, volume data |
| monit | **`monit -t`** (test syntaxe), scripts, conf.d/, service systemd |
| alloy | `alloy --version`, service systemd, config exists |
| telegram_bot | Service systemd, venv Python, bot.py exists, `.env` mode 600 |

> **⚠️ Règle absolue :** JAMAIS de `failed_when: false` dans les `verify.yml`. Ça rend le test inopérant (il passe toujours, même si la vérification échoue).

---

## Molecule — Bonnes pratiques CI/CD (REX v3.0.0)

Ces règles sont issues des 5 rounds de debugging du pipeline CI/CD. Elles s'appliquent à TOUS les rôles.

### Règle 1 : Tout `prepare.yml` commence par les prérequis CI

```yaml
# prepare.yml — bloc obligatoire en début
- name: Install CI prerequisites
  ansible.builtin.apt:
    name:
      - lsb-release
      - python3-requests
      - gnupg
    state: present
    update_cache: true
```

### Règle 2 : Toute tâche `shell` avec pipe → `/bin/bash`

```yaml
# ❌ Échoue en CI (dash ≠ bash)
- ansible.builtin.shell:
    cmd: curl -fsSL ... | gpg ...

# ✅ Fonctionne partout
- ansible.builtin.shell:
    executable: /bin/bash
    cmd: |
      set -o pipefail
      curl -fsSL ... | gpg ...
```

### Règle 3 : DinD — monter des répertoires, JAMAIS des fichiers

```yaml
# ❌ Échoue en DinD (le fichier est créé comme répertoire sur l'hôte)
volumes:
  - ./Caddyfile:/etc/caddy/Caddyfile:ro

# ✅ Fonctionne en DinD
volumes:
  - ./conf:/etc/caddy:ro
```

### Règle 4 : Skip idempotence pour les conteneurs crash-loop

Les conteneurs sans DNS ni config complète crash-loop en CI. Le test d'idempotence donne des faux négatifs. Supprimer `idempotence` du `test_sequence` dans `molecule.yml` pour ces rôles.

### Règle 5 : Services → retries dans verify.yml

```yaml
- name: Wait for service to be active
  ansible.builtin.service_facts:
  register: _svc
  until: _svc.ansible_facts.services['telegram-bot.service'].state == 'running'
  retries: 3
  delay: 5
```
