# 🏗️ Architecture Seko-VPN V3

> Ce document décrit l'architecture complète du projet : les services déployés, le réseau, le monitoring et le hardening système. Il est conçu pour qu'un technicien junior puisse comprendre comment tous les composants s'articulent.

---

## 1. Vue d'ensemble

Seko-VPN déploie automatiquement une infrastructure self-hosted complète sur un VPS Debian. L'objectif est le **"fire-and-forget"** : une fois déployé, le serveur se maintient seul (mises à jour de sécurité, rotation des logs, monitoring, alertes, auto-remédiation).

L'opérateur supervise depuis son téléphone via Telegram.

### Ce que Seko-VPN installe

```
┌─────────────────────────────────────────────────────────────┐
│                    Internet (HTTPS :443)                     │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│                     CADDY (reverse proxy)                    │
│              SSL auto · HSTS · HTTP/2 · ci_mode              │
│  hs. │ nga. │ vault. │ portainer. │ zb. │ status.           │
│  (6 vhosts — PAS de vhost Monit en V3)                      │
└──┬───────┬──────┬───────┬──────────┬──────┬────────────────┘
   │       │      │       │          │      │
   ▼       ▼      ▼       ▼          ▼      ▼
┌──────┐┌──────┐┌──────┐┌─────────┐┌────┐┌──────────────┐
│Head- ││Head- ││Vault-││Portainer││Zero││Uptime Kuma   │
│scale ││plane ││warden││  :9000  ││byte││  :3001       │
│:8080 ││:3000 ││ :80  ││         ││4096││              │
└──────┘└──────┘└──────┘└─────────┘└────┘└──────────────┘
   └───────────────── proxy-net ──────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                 Services natifs (apt / pip)                   │
├─────────────────┬─────────────────┬─────────────────────────┤
│ Monit HEADLESS  │ Grafana Alloy   │ Telegram Bot            │
│ (watchdog)      │ (collecteur)    │ (Python interactif)     │
│ alertes Telegram│ prêt pour Loki  │ /status /restart ...    │
│ PAS de web      │                 │                         │
└─────────────────┴─────────────────┴─────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                Hardening production                           │
│  journald 500M · logrotate · chrony NTP · swap 2G           │
│  unattended-upgrades · docker-prune timer · sysctl           │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Les trois couches de services

### 2.1 Couche Docker — Les 8 conteneurs

Tous les conteneurs partagent un unique réseau Docker bridge nommé `proxy-net`. **Seul Caddy expose des ports vers l'extérieur** (80 et 443). Les autres conteneurs communiquent entre eux en interne sur ce réseau.

| # | Service | Image | Port interne | Sous-domaine | Rôle |
|---|---------|-------|-------------|--------------|------|
| 1 | **Headscale** | `headscale/headscale:0.26.0` | 8080 | `hs.` | Serveur VPN WireGuard (remplace un serveur VPN classique) |
| 2 | **Headplane** | `ghcr.io/tale/headplane:latest` | 3000 | `nga.` | Interface web pour gérer les clients VPN Headscale |
| 3 | **Vaultwarden** | `vaultwarden/server:1.35.1-alpine` | 80 | `vault.` | Gestionnaire de mots de passe (compatible Bitwarden) |
| 4 | **Portainer** | `portainer/portainer-ce:lts` | 9000 | `portainer.` | Interface web pour gérer les conteneurs Docker |
| 5 | **Zerobyte** | `ghcr.io/borgbase/vorta:v0.25.1` | 4096 | `zb.` | Sauvegardes chiffrées (basé sur Restic) |
| 6 | **Uptime Kuma** | `louislam/uptime-kuma:latest` | 3001 | `status.` | Monitoring HTTP/TCP/DNS avec dashboard web et historique SLA |
| 7 | **Caddy** | `caddy:latest` | 80/443 | — | Reverse proxy avec SSL automatique Let's Encrypt |

> **💡 Pourquoi proxy-net ?** Un seul réseau simplifie la configuration. Caddy connaît les noms des conteneurs (ex: `headscale:8080`) et route le trafic automatiquement. Aucun conteneur n'a besoin d'exposer ses ports sur l'hôte.

### 2.2 Couche native — Les 3 services système

Ces services sont installés directement sur le système (via `apt` ou `pip`), pas dans Docker.

| # | Service | Installation | Rôle |
|---|---------|-------------|------|
| 1 | **Monit** | apt | Watchdog système : surveille les processus, redémarre automatiquement en cas de crash, envoie des alertes Telegram. Mode **HEADLESS** (pas d'interface web) |
| 2 | **Grafana Alloy** | apt (dépôt Grafana officiel) | Collecteur de logs Docker et journaux systemd. Prêt à envoyer vers un serveur Loki quand il sera disponible |
| 3 | **Bot Telegram** | Python + systemd | Bot interactif pour superviser le serveur depuis Telegram : `/status`, `/restart`, `/logs`, `/disk` |

> **💡 Pourquoi Monit est HEADLESS en V3 ?** En V1/V2, Monit avait une interface web exposée via Caddy. Cela causait des problèmes récurrents (ACL, réseau Docker, caractères spéciaux). En V3, Uptime Kuma remplace la UI web et Monit reste concentré sur son rôle de watchdog. L'accès admin se fait en SSH : `sudo monit status`.

### 2.3 Couche hardening — La protection système

Le rôle `hardening` configure le serveur pour la production long terme :

| Composant | Ce qu'il fait | Pourquoi c'est important |
|-----------|--------------|-------------------------|
| **journald** | Limite les logs à 500 Mo, rétention 30 jours | Sans ça, `/var/log/journal` grossit indéfiniment → disque plein |
| **logrotate** | Rotation des logs Monit, Alloy, Telegram Bot | Les services custom n'ont pas de rotation par défaut |
| **chrony** | Synchronisation NTP | Évite le drift d'horloge → certificats TLS rejetés, logs incohérents |
| **swap** | 2 Go si RAM < 4 Go | Empêche l'OOM killer de tuer les conteneurs Docker |
| **unattended-upgrades** | Mises à jour sécurité automatiques | Patch les CVE sans intervention manuelle |
| **docker-prune** | Timer hebdomadaire | Nettoie les images et volumes orphelins Docker |
| **sysctl** | `kernel.panic=10`, `fs.file-max=2097152` | Auto-reboot après kernel panic, limite de fichiers ouverts augmentée |

---

## 3. Le réseau

### 3.1 Flux réseau entrant

```
Client HTTPS ──► Caddy :443 ──► Conteneur backend (port interne)
                    │
                    ├── hs.example.com     → headscale:8080
                    ├── nga.example.com    → headplane:3000
                    ├── vault.example.com  → vaultwarden:80
                    ├── portainer.example.com → portainer:9000
                    ├── zb.example.com     → zerobyte:4096
                    └── status.example.com → uptime-kuma:3001
```

### 3.2 Les 6 vhosts Caddy V3

| # | Domaine | Backend | Particularités |
|---|---------|---------|---------------|
| 1 | `hs.example.com` | headscale:8080 | VPN WireGuard — nécessite WebSocket |
| 2 | `nga.example.com` | headplane:3000 | Image distroless → `redir / /admin permanent` obligatoire |
| 3 | `vault.example.com` | vaultwarden:80 | Notifications WebSocket sur `/notifications/hub` |
| 4 | `portainer.example.com` | portainer:9000 | Interface Docker |
| 5 | `zb.example.com` | zerobyte:4096 | Sauvegardes |
| 6 | `status.example.com` | uptime-kuma:3001 | Dashboard monitoring HTTP |

> **⚠️ En V3, il n'y a PAS de vhost Monit.** C'est intentionnel. Monit est headless et accessible uniquement en SSH.

### 3.3 Ports ouverts (UFW)

| Port | Protocol | Usage |
|------|----------|-------|
| 22 (puis custom) | TCP | SSH |
| 80 | TCP | HTTP (redirection vers HTTPS) |
| 443 | TCP | HTTPS (Caddy) |
| 41641 | UDP | WireGuard (Headscale) |

Tous les autres ports sont bloqués par UFW. Fail2Ban surveille les tentatives SSH.

---

## 4. Le monitoring (4 composants)

Le monitoring V3 repose sur 4 outils complémentaires. Chacun fait une chose et la fait bien :

```
Services (conteneurs + apt)
      │
      ├── Monit (watchdog HEADLESS)
      │   ├── Vérifie : processus, CPU, RAM, disque
      │   ├── Auto-remédie : restart si crash
      │   └── Alerte → Telegram (unidirectionnel)
      │
      ├── Uptime Kuma (monitoring HTTP)
      │   ├── Vérifie : endpoints HTTPS, TCP, DNS
      │   ├── Historique : graphiques, SLA %
      │   └── UI web : status.example.com
      │
      ├── Grafana Alloy (collecteur logs)
      │   ├── Collecte : Docker logs, journald
      │   └── Envoi : → Loki (quand disponible en V4)
      │
      └── Telegram Bot (opérations interactives)
          ├── Commandes : /status /containers /disk /logs
          ├── Actions : /restart (avec confirmation)
          └── Identifie : [seko-vpn-01] devant chaque réponse
```

### Qui fait quoi ?

| Outil | Détection | Auto-fix | Dashboard | Interactif |
|-------|-----------|----------|-----------|------------|
| Monit | ✅ | ✅ (restart) | ❌ | ❌ |
| Uptime Kuma | ✅ | ❌ | ✅ (web) | ❌ |
| Alloy | ❌ (collecte) | ❌ | ❌ | ❌ |
| Telegram Bot | ✅ (sur demande) | ✅ (/restart) | ❌ | ✅ |

### Services surveillés par Monit (11 checks)

| # | Service | Type | Action si crash |
|---|---------|------|-----------------|
| 1 | Docker daemon | systemd | restart + alerte Telegram |
| 2-8 | 7 conteneurs | Docker | restart + alerte Telegram |
| 9 | Alloy | systemd | restart + alerte Telegram |
| 10 | Telegram Bot | systemd | restart + alerte Telegram |
| 11 | Système | CPU/RAM/disque | alerte uniquement |

### Commandes du Bot Telegram

| Commande | Action | Exemple de sortie |
|----------|--------|-------------------|
| `/status` | `monit summary` | État de tous les services |
| `/containers` | `docker ps --format` | Liste des conteneurs et leur état |
| `/disk` | `df -h` | Utilisation disque |
| `/logs headscale` | Dernières 20 lignes de logs | Logs Docker ou journalctl |
| `/restart vaultwarden` | Redémarrage avec confirmation | Demande `/restart_confirm` avant d'agir |
| `/uptime` | `uptime` | Durée uptime + load average |
| `/help` | Liste des commandes | Description de chaque commande |

> **🔒 Sécurité du bot :** Le bot ne répond qu'aux `ALLOWED_CHAT_IDS` configurés. La commande `/restart` demande toujours une confirmation. Chaque réponse est préfixée par `[nom-du-serveur]` pour le futur multi-serveur V4.

---

## 5. Gestion des secrets

### Secrets dans vault.yml (chiffré par ansible-vault)

| Secret | Contrainte | Généré automatiquement par wizard.sh |
|--------|-----------|--------------------------------------|
| `vault_system_user_password` | Base64, 24 chars | ✅ |
| `vault_vaultwarden_admin_token` | Base64, 32 chars | ✅ |
| `vault_headplane_cookie_secret` | Exactement 32 chars | ✅ |
| `vault_zerobyte_app_secret` | Hex, exactement 64 chars | ✅ |
| `vault_monit_password` | Alphanumérique uniquement, 16 chars | ✅ |
| `vault_telegram_bot_token` | Token API Telegram | ❌ (demandé au wizard) |
| `vault_telegram_chat_id` | Chat ID numérique | ❌ (demandé au wizard) |

> **⚠️ Contraintes critiques sur les secrets :**
>
> - **Monit** : le mot de passe ne doit contenir QUE des lettres et chiffres (pas de `"`, `#`, `{`, `}`). Sinon Monit refuse de démarrer.
> - **Zerobyte** : `APP_SECRET` doit faire exactement 64 caractères hexadécimaux. Sinon le conteneur refuse de démarrer.
> - **Headplane** : `COOKIE_SECRET` doit faire exactement 32 caractères. Sinon l'authentification échoue.

### Secrets CI/CD (GitHub Actions)

| Secret | Usage |
|--------|-------|
| `HCLOUD_TOKEN` | Créer/détruire les VM éphémères Hetzner |
| `SSH_PRIVATE_KEY` | Connexion SSH aux VM de test |
| `VAULT_PASSWORD` | Déchiffrer vault.yml pendant les tests |

---

## 6. Arborescence du projet

```
Seko-VPN/
├── ansible.cfg                              # Config Ansible (chemins, options)
├── requirements.yml                         # Collections Ansible requises
├── requirements-dev.txt                     # Dépendances dev (Molecule, lint)
├── Makefile                                 # Commandes make (lint, molecule, etc.)
├── .yamllint                                # Config yamllint
├── .ansible-lint                            # Config ansible-lint (profil production)
├── .github/workflows/
│   └── ci.yml                               # Pipeline CI/CD (3 stages)
├── inventory/
│   ├── hosts.yml                            # IP du serveur cible
│   └── group_vars/all/
│       ├── vars.yml                         # Variables publiques
│       └── vault.yml                        # Secrets (chiffrés)
├── playbooks/
│   ├── site.yml                             # Déploie les 14 rôles dans l'ordre
│   ├── harden-ssh.yml                       # Hardening SSH (post-validation)
│   ├── verify.yml                           # Vérification automatisée
│   └── wsl-repair.yml                       # Répare DNS/systemd WSL2
├── scripts/
│   ├── wizard.sh                            # Configuration interactive
│   ├── bootstrap-vps.sh                     # Préparation VPS (user + SSH + sudo)
│   ├── setup-ci.sh                          # Installation env CI local
│   └── fix-lint.sh                          # Correction auto violations lint
├── templates/                               # Templates pour wizard.sh
│   ├── vars.yml.j2
│   └── vault.yml.j2
├── tests/
│   └── ci-vars.yml                          # Variables CI (ci_mode: true)
├── docs/                                    # Cette documentation
└── roles/                                   # 14 rôles Ansible
    ├── common/          # 1. Utilisateur, paquets, locale
    ├── security/        # 2. UFW, Fail2Ban, sysctl
    ├── docker/          # 3. Docker Engine 29 + Compose v5
    ├── hardening/       # 4. journald, logrotate, chrony, swap...
    ├── caddy/           # 5. Reverse proxy (6 vhosts)
    ├── headscale/       # 6. VPN WireGuard
    ├── headplane/       # 7. UI VPN (distroless)
    ├── vaultwarden/     # 8. Mots de passe
    ├── portainer/       # 9. UI Docker
    ├── zerobyte/        # 10. Sauvegardes
    ├── uptime_kuma/     # 11. Monitoring HTTP
    ├── monit/           # 12. Watchdog HEADLESS
    ├── alloy/           # 13. Collecteur logs
    └── telegram_bot/    # 14. Bot Telegram
```

---

## 7. Ordre d'exécution des rôles

Les 14 rôles s'exécutent dans un ordre précis (défini dans `playbooks/site.yml`). L'ordre est important car certains rôles dépendent des précédents.

```
1.  common          → Utilisateur système, paquets de base, locale
2.  security        → UFW, Fail2Ban, sysctl sécurité
3.  docker          → Docker Engine 29, Compose v5, réseau proxy-net
4.  hardening       → journald, logrotate, chrony, swap, unattended-upgrades
5.  caddy           → Reverse proxy avec 6 vhosts + SSL
6.  headscale       → Serveur VPN
7.  headplane       → Interface web VPN
8.  vaultwarden     → Gestionnaire de mots de passe
9.  portainer       → Interface Docker
10. zerobyte        → Sauvegardes
11. uptime_kuma     → Monitoring HTTP
12. monit           → Watchdog système (surveille TOUS les services ci-dessus)
13. alloy           → Collecteur de logs
14. telegram_bot    → Bot Telegram interactif
```

> **💡 Pourquoi cet ordre ?** Les rôles infrastructure (Docker, Caddy) doivent être prêts AVANT les services applicatifs. Monit vient APRÈS tous les services car il doit les surveiller. Le bot Telegram vient en dernier car il utilise Monit pour `/status`.

---

## 8. Exigences serveur

### Machine cible (VPS)

| Élément | Minimum | Recommandé |
|---------|---------|------------|
| OS | Debian 12 | Debian 13 |
| CPU | 2 vCPU | 2+ vCPU |
| RAM | 2 Go | 4 Go |
| Disque | 20 Go | 40 Go |
| Domaine | 1 domaine + accès DNS | — |

### Machine locale (opérateur)

| Élément | Version |
|---------|---------|
| Python | 3.11+ |
| Ansible | 2.20+ |
| SSH | Clé Ed25519 |
| Git | 2.x+ |
