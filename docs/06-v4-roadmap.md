# 🗺️ Feuille de route V4 — Axes d'amélioration

> Ce document présente les améliorations prévues pour la V4 de Seko-VPN, avec leur priorisation, leur effort estimé et leur architecture cible. Ces éléments étaient **hors périmètre V3** par choix.

---

## Ce qui a été réalisé en V3

Avant de parler du futur, rappelons ce que V3 a ajouté par rapport à V2 :

| # | Amélioration | Statut |
|---|-------------|--------|
| 1 | Hardening sysadmin (journald, logrotate, chrony, swap, unattended-upgrades) | ✅ V3 |
| 2 | Uptime Kuma + Monit headless | ✅ V3 |
| 3 | Grafana Alloy pré-installé | ✅ V3 |
| 4 | Bot Telegram interactif | ✅ V3 |
| 5 | Wizard de configuration | ✅ V3 |
| 6 | CI mode local_certs | ✅ V3 |
| 7 | Docker prune timer | ✅ V3 |
| 8 | Kernel panic auto-reboot | ✅ V3 |
| 9 | **Pipeline CI/CD 3 stages validé** (lint + 14 rôles Molecule + intégration Hetzner) | ✅ V3.0.0 |
| 10 | **42 pièges documentés** (REX Day 0 → Round 5) | ✅ V3.0.0 |
| 11 | **Bonnes pratiques DinD** (bind mounts, idempotence, Debian 13) | ✅ V3.0.0 |

---

## Matrice de priorisation V4

| # | Amélioration | Impact | Effort | Priorité |
|---|-------------|--------|--------|----------|
| 1 | SSO/OIDC centralisé | 🔴 Élevé (sécurité) | 2-3 jours | 🔴 Haute |
| 2 | Backup chiffré vers S3 | 🔴 Élevé (résilience) | 1-2 jours | 🔴 Haute |
| 3 | Multi-serveur Telegram | 🔴 Élevé (opérations) | 2-3 jours | 🔴 Haute |
| 3b | Security Hardening V3.2 | 🔴 Élevé (sécurité) | 2-3 jours | 🔴 Haute |
| 4 | Scanning de vulnérabilités (Trivy) | 🟡 Moyen (sécurité) | 1 jour | 🟡 Moyenne |
| 5 | Support multi-OS | 🟡 Moyen (portabilité) | 3-5 jours | 🟡 Moyenne |
| 6 | Stack observabilité complète | 🟡 Moyen (visibilité) | 3-4 jours | 🟡 Moyenne |
| 7 | Rotation automatique des secrets | 🟢 Faible (sécurité) | 1-2 jours | 🟢 Basse |
| 8 | Tests Molecule avancés | 🟢 Faible (qualité) | 2 jours | 🟢 Basse |
| 9 | Wizard GUI web | 🟢 Faible (UX) | 2-3 jours | 🟢 Basse |

> **Recommandation :** Commencer par SSO (1) + Backup S3 (2) + Multi-serveur Telegram (3). Ces trois éléments transforment la stack d'un déploiement mono-serveur en une plateforme multi-serveurs sécurisée et résiliente.

---

## 1. SSO/OIDC centralisé

**Priorité : 🔴 Haute** · **Effort : 2-3 jours**

### Problème actuel

Chaque service a son propre système d'authentification. L'opérateur doit gérer N mots de passe différents. Pas de 2FA centralisé. Pas de révocation centralisée des accès.

### Solution V4

Déployer **Authelia** comme Identity Provider (IdP) centralisé :

```
Client HTTPS
    │
    ▼
┌─────────────────────────────────────────────────────────┐
│ Caddy                                                    │
│  ├── forward_auth authelia:9091 ──► Authelia            │
│  │       │                          (vérifie l'identité)│
│  │       │ ✅ Authentifié                                │
│  │       ▼                                               │
│  ├── portainer.example.com → Portainer                  │
│  ├── zb.example.com → Zerobyte                          │
│  └── status.example.com → Uptime Kuma                   │
│                                                          │
│  Services avec SSO natif (pas de forward_auth) :         │
│  ├── vault.example.com → Vaultwarden (OIDC natif)       │
│  └── nga.example.com → Headplane (OIDC natif)           │
└─────────────────────────────────────────────────────────┘
```

### Ce que ça apporte

- Un seul login pour tous les services
- 2FA centralisé (TOTP, WebAuthn)
- Révocation instantanée d'un accès
- Audit log centralisé des connexions
- Nouveau rôle Ansible : `authelia`

---

## 2. Backup chiffré vers S3

**Priorité : 🔴 Haute** · **Effort : 1-2 jours**

### Problème actuel

Zerobyte est installé mais non configuré avec un backend de stockage distant. Si le VPS est perdu (crash disque, erreur hébergeur), toutes les données sont perdues.

### Solution V4

Pré-configurer Zerobyte avec un repository S3 (Backblaze B2 ou Wasabi) :

```
Zerobyte (VPS) ──► Chiffrement local ──► S3 (Backblaze B2 / Wasabi)
                                              │
                                              ├── Backup quotidien incrémental
                                              ├── Backup hebdomadaire complet
                                              └── Rétention : 30 jours
```

### Variables à ajouter dans vault.yml

```yaml
vault_s3_access_key: "xxx"
vault_s3_secret_key: "xxx"
vault_s3_bucket: "seko-vpn-backups"
vault_s3_endpoint: "s3.eu-central-003.backblazeb2.com"
```

### Monitoring des backups

Ajouter un check Monit qui vérifie le timestamp du dernier backup :
- Si le dernier backup date de plus de 48h → alerte Telegram
- Test de restauration automatisé dans le pipeline CI

---

## 3. Multi-serveur Telegram Bot

**Priorité : 🔴 Haute** · **Effort : 2-3 jours**

### Problème actuel

Le bot Telegram V3 est local à un seul serveur. Si tu gères 3 VPS, tu as 3 bots différents sur 3 conversations Telegram distinctes.

### Solution V4

```
Telegram → Bot central (VPS dédié ou serverless)
              │
              ├── /status vps1  → Agent VPS1 (via Headscale VPN)
              ├── /status vps2  → Agent VPS2 (via Headscale VPN)
              ├── /status all   → Tous les agents
              └── /restart vps1 caddy → Agent VPS1 (avec confirmation)
```

### Architecture

- **Bot central** : reçoit les commandes Telegram, dispatch vers les agents
- **Agents légers** : API REST (FastAPI) sur chaque VPS, communiquent via le VPN Headscale
- **Sécurité** : les agents ne sont PAS exposés sur internet, ils écoutent uniquement sur le réseau VPN

### Préparation V3

Le bot V3 est déjà préparé pour ça : chaque réponse est préfixée par `[nom-du-serveur]` (variable `telegram_bot_server_name`).

---

## 3b. Security Hardening V3.2

**Priorité : 🔴 Haute** · **Effort : 2-3 jours** · **Pré-requis : second serveur VPN opérationnel**

### Contexte

Audit de sécurité réalisé post-V3.1. Le serveur est fonctionnel mais présente des surfaces d'attaque réductibles. Ce durcissement doit être déployé **après** avoir validé le VPN multi-serveur (A → B → C) pour éviter de se verrouiller dehors.

### 9 axes de durcissement (par ordre de déploiement)

| # | Axe | Risque | Effort | Impact |
|---|-----|--------|--------|--------|
| 1 | **Pin images `latest`** | Risque zéro | 10 min | Headplane et Uptime Kuma utilisent `latest`. Pinner sur un tag précis empêche les régressions silencieuses |
| 2 | **Container capability dropping** | Faible | 30 min | Ajouter `cap_drop: ALL` + `cap_add` minimaux dans chaque `docker-compose.yml.j2`. Réduit la surface d'attaque en cas de compromission d'un conteneur |
| 3 | **Fail2Ban HTTP jails** | Faible | 1h | Ajouter des jails Fail2Ban pour les 401/403 Caddy. Bloque le brute-force sur les interfaces web (Portainer, Vaultwarden, Headplane) |
| 4 | **Rate limiting Caddy** | Faible | 1h | Limiter les requêtes par IP sur les vhosts sensibles (login pages). Complète Fail2Ban |
| 5 | **ACL Headscale granulaires** | Moyen | 2h | Remplacer la policy `allow-all` par des groups/roles. Contrôler qui peut communiquer avec qui dans le VPN |
| 6 | **Docker socket proxy** | Moyen | 2h | Remplacer le bind mount `/var/run/docker.sock` par un proxy Tecnativa en read-only. Protège Portainer et Alloy |
| 7 | **Segmentation réseau Docker** | Moyen | 2h | Ajouter un réseau `mgmt-net` dédié à Portainer + socket-proxy (Tecnativa). Conditionnel à l'axe 6 (socket proxy). Seko-VPN n'a pas de DB partagée : un seul réseau `proxy-net` suffit pour les 7 services applicatifs |
| 8 | **SSH via VPN uniquement** | Élevé | 1h | Restreindre UFW pour n'autoriser SSH que depuis le subnet VPN (100.64.0.0/10). **Pré-requis** : VPN multi-serveur validé + porte de secours IPMI/KVM |
| 9 | **AppArmor profiles** | Optionnel | 4h+ | Profils AppArmor custom par conteneur. Complexe, bénéfice marginal si les autres axes sont en place |

### Déploiement recommandé

```
Phase 1 (immédiat, zéro risque) : axes 1-2
Phase 2 (protection réseau)     : axes 3-4-5
Phase 3 (isolation avancée)     : axes 6-7
Phase 4 (verrouillage final)    : axe 8 (après multi-serveur)
Phase 5 (optionnel)             : axe 9
```

### Fichiers principaux impactés

- `roles/*/templates/docker-compose.yml.j2` — cap_drop, réseaux
- `roles/security/tasks/main.yml` — Fail2Ban jails, UFW VPN-only
- `roles/caddy/templates/Caddyfile.j2` — rate limiting
- `roles/headscale/templates/policy.json.j2` — ACL granulaires
- `roles/docker/tasks/main.yml` — création du réseau `mgmt-net`, socket proxy

---

## 4. Scanning de vulnérabilités (Trivy)

**Priorité : 🟡 Moyenne** · **Effort : 1 jour**

### Ce que ça fait

Intégrer Trivy dans le pipeline CI pour scanner les 8 images Docker à chaque merge sur `main` :

```
Merge sur main
    │
    ▼
┌────────────────────────────────────────┐
│ Stage : Security Scan                   │
│                                         │
│ trivy image headscale/headscale:0.26.0 │
│ trivy image vaultwarden/server:1.35.1  │
│ trivy image caddy:latest               │
│ ... (8 images)                          │
│                                         │
│ Si CRITICAL → ❌ Pipeline bloqué        │
│ Si HIGH → ⚠️ Warning (ne bloque pas)   │
│                                         │
│ Rapport Markdown → artefact CI          │
└────────────────────────────────────────┘
```

---

## 5. Support multi-OS

**Priorité : 🟡 Moyenne** · **Effort : 3-5 jours**

### OS cibles

| OS | Priorité | Difficulté | Notes |
|----|----------|-----------|-------|
| Ubuntu 22.04/24.04 | P1 | Faible | Noms de paquets similaires, dépôts Docker identiques |
| Rocky Linux 9 | P2 | Moyenne | `dnf` au lieu de `apt`, `firewalld` au lieu de UFW, SELinux |

### Impact sur le projet

- Conditionner les tâches avec `ansible_os_family` ou `ansible_distribution`
- Étendre la matrice Molecule : `debian12 + ubuntu2404`
- Adapter les noms de paquets et chemins de config

---

## 6. Stack observabilité complète

**Priorité : 🟡 Moyenne** · **Effort : 3-4 jours**

### Architecture cible

Grafana Alloy est déjà en place (V3). Il suffit de déployer le backend :

```
┌──────────────────┐     ┌──────────────────┐
│ VPS Seko-VPN     │     │ VPS Monitoring   │
│                  │     │ (dédié)          │
│ Grafana Alloy ──────────► Loki (logs)    │
│ cAdvisor ────────────────► Prometheus     │
│                  │     │                  │
│                  │     │ Grafana ◄── dashboards + alertes
└──────────────────┘     └──────────────────┘
```

### Nouveaux composants

- **Loki** : stockage et indexation des logs (receveur pour Alloy)
- **Prometheus** : métriques système et conteneurs
- **cAdvisor** : métriques détaillées des conteneurs Docker
- **Grafana** : dashboards et alertes visuelles

### Activation sur V3 existant

Pour connecter un VPS V3 existant à un serveur Loki :

```bash
ansible-vault edit inventory/group_vars/all/vars.yml
# Modifier : alloy_loki_url: "http://loki.monitoring.example.com:3100/loki/api/v1/push"
ansible-playbook playbooks/site.yml --tags alloy --ask-vault-pass
```

---

## 7. Rotation automatique des secrets

**Priorité : 🟢 Basse** · **Effort : 1-2 jours**

### Concept

Un playbook `rotate-secrets.yml` qui :

1. Génère de nouveaux secrets (mêmes contraintes que wizard.sh)
2. Met à jour `vault.yml`
3. Redémarre les services impactés dans le bon ordre
4. Vérifie que tout fonctionne
5. Notifie via Telegram
6. Log l'opération

---

## 8. Tests Molecule avancés

**Priorité : 🟢 Basse** · **Effort : 2 jours**

### Améliorations prévues

- **Tests Testinfra** (Python) en plus des assertions Ansible — plus de flexibilité
- **Test d'idempotence** : double converge, vérifier `changed=0` au second run
- **Matrice étendue** : Debian 12 / Debian 13 dans le pipeline
- **Scénario multi-rôles** : les 14 rôles enchaînés dans l'ordre (comme `site.yml`)

---

## 9. Wizard GUI web

**Priorité : 🟢 Basse** · **Effort : 2-3 jours**

Alternative au wizard.sh CLI : une page HTML simple servie localement avec :
- Formulaire avec tous les champs
- Validation en temps réel (ex: vérifier que l'IP est valide)
- Génération des fichiers YAML
- Affichage des enregistrements DNS à créer

Destiné aux opérateurs moins techniques qui préfèrent une interface graphique.

---

## Résumé de l'évolution V1 → V4

| Métrique | V1 | V2 | V3 | V4 (cible) |
|----------|----|----|-----|------------|
| Rôles Ansible | 10 | 10 | 14 | 15-16 |
| Services Docker | 7 | 7 | 8 | 9-10 |
| Services natifs | 1 | 1 | 3 | 3-4 |
| Scénarios Molecule | 0 | 10 | 14 | 16+ |
| Pipeline CI stages | 0 | 3 | 3 | 4 (+ security) |
| OS supportés | 1 | 1 | 1 | 2-3 |
| Authentification | Individuelle | Individuelle | Individuelle | SSO centralisé |
| Backup S3 | ❌ | ❌ | ❌ | ✅ |
| Multi-serveur | ❌ | ❌ | Préparé | ✅ |
