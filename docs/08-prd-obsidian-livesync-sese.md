# 📋 PRD — Obsidian LiveSync sur sese (VPAI)

> **Product Requirements Document** · Statut : Draft v1.1 · Auteur : mmomb · Date : 2026-02
>
> Ce document décrit l'ajout d'**Obsidian LiveSync** (CouchDB) sur le serveur `sese` (VPAI) en tant que hub de connaissance Markdown partagé entre Obsidian, OpenClaw et un futur Nextcloud.

---

## 1. Contexte et problème

### 1.1 Situation actuelle

Le réseau Headscale coordonné par Seko-VPN (IONOS) interconnecte deux serveurs actifs :

| Nœud | IP publique | IP Tailscale | Rôle actuel |
|------|-------------|--------------|-------------|
| `vps` (IONOS) | `87.106.30.160` | Coordinateur | Seko-VPN — 14 rôles (VPN, proxy, vault, monitoring…) |
| `sese` (Javisi) | `137.74.114.167` | `100.64.0.14` | VPAI — n8n, LiteLLM, Grafana, Qdrant… |
| `ewutelo` (Windows) | — | `100.64.0.2` | Machine de développement |

`sese` est géré par un **playbook Ansible dédié** avec **Caddy** comme reverse proxy — même pattern que Seko-VPN (IONOS).

### 1.2 Problème à résoudre

Il n'existe pas de **base de connaissance Markdown centralisée et synchronisée** accessible :
- depuis Obsidian sur les clients (desktop + mobile)
- depuis OpenClaw (agent IA local sur `sese`) pour ses workflows
- depuis les outils d'automatisation n8n déjà présents sur `sese`
- avec une trajectoire vers un backup/archivage Nextcloud futur

Aujourd'hui, les notes restent locales sur la machine de développement (`ewutelo`) et ne sont pas disponibles pour l'IA.

### 1.3 Objectif

Déployer un service de synchronisation **Obsidian LiveSync (CouchDB 3.x)** sur `sese`, exposé via **Caddy en HTTPS** sur `biki.ewutelo.cloud` (accessible publiquement), pour centraliser les fichiers Markdown en tant que source de vérité unique pour Obsidian et OpenClaw — sans nécessiter Tailscale comme prérequis client.

---

## 2. Décision d'architecture : vhost Caddy public vs. Tailscale-only

### Choix retenu : Caddy HTTPS public sur `biki.ewutelo.cloud`

| Critère | Tailscale-only (rejeté) | Caddy HTTPS public ✅ |
|---------|------------------------|----------------------|
| Debug Fauxton (`/_utils`) | SSH tunnel obligatoire | Navigateur direct |
| Clients mobiles | Tailscale requis sur chaque appareil | Plugin Obsidian natif, zéro config VPN |
| TLS valide | WireGuard tunnel (pas de cert LE) | Let's Encrypt automatique via Caddy |
| Cohérence avec sese | Dérogatoire (Caddy inutilisé) | ✅ Même pattern que tous les services |
| Sécurité données | OK (tunnel chiffré) | ✅ Données E2E chiffrées par LiveSync côté client |

**Justification sécurité :** Le vault Obsidian LiveSync est chiffré de bout en bout **avant** d'arriver sur CouchDB. Le serveur CouchDB ne voit que des blobs chiffrés — il ne peut pas lire le contenu des notes. Exposer l'endpoint sur internet public ne compromet pas la confidentialité du vault.

L'authentification CouchDB (user/password) reste la barrière d'accès, protégée par HTTPS Let's Encrypt.

---

## 3. Cas d'usage

### UC-01 — Synchronisation Obsidian multi-devices

```
[Obsidian Desktop (ewutelo)]
[Obsidian Mobile (iOS/Android)]  ──► https://biki.ewutelo.cloud ──► CouchDB (sese)
[Obsidian Desktop (autre PC)]
```

L'utilisateur édite des notes dans Obsidian sur n'importe quel appareil. Les modifications sont synchronisées en temps réel via le plugin Self-hosted LiveSync vers CouchDB sur `sese` via HTTPS. Aucun prérequis VPN côté client.

### UC-02 — Base de connaissance pour OpenClaw

```
CouchDB (sese:5984, réseau Docker interne)
    │ export périodique (n8n workflow)
    ▼
/opt/services/obsidian-vault/ (fichiers .md sur filesystem sese)
    │
    ▼
OpenClaw lit les .md ──► LiteLLM ──► Workflows n8n
```

OpenClaw dispose d'un répertoire local de fichiers Markdown à jour, mis à jour automatiquement depuis CouchDB via un workflow n8n. Le contenu reste chiffré dans CouchDB — l'export n8n déchiffre les documents pour les écrire en `.md` lisibles sur le filesystem.

> **Note :** OpenClaw peut aussi interroger CouchDB directement via son API si les documents sont stockés en clair (sans E2E). Si le chiffrement E2E est activé, l'export n8n est obligatoire pour produire des `.md` lisibles.

### UC-03 — Archivage futur vers Nextcloud (Phase 4)

```
/opt/services/obsidian-vault/ ──► n8n workflow ──► WebDAV PUT ──► Nextcloud (futur VPS)
```

Le répertoire filesystem (déjà peuplé par UC-02) est pushé vers Nextcloud via WebDAV. Nextcloud joue le rôle d'archive longue durée, PAS de sync concurrent.

> ⚠️ **Incompatibilité critique :** Obsidian LiveSync et Nextcloud ne peuvent PAS synchroniser le même vault simultanément. Nextcloud est une destination de backup en écriture seule depuis n8n, jamais un client LiveSync.

---

## 4. Architecture cible

### 4.1 Vue réseau complète

```
Internet (HTTPS :443)
        │
        ▼
┌───────────────────────────────────────────────────────────────┐
│              sese / VPAI — 137.74.114.167 (Javisi)           │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  Caddy (existant sur sese)                              │ │
│  │                                                         │ │
│  │  biki.ewutelo.cloud → couchdb:5984  (NOUVEAU vhost)    │ │
│  │  [autres vhosts sese existants...]                      │ │
│  └──────────────────────────┬──────────────────────────────┘ │
│                             │ réseau Docker interne sese      │
│  ┌──────────────────────────▼──────────────────────────────┐ │
│  │  CouchDB 3.3.3                                          │ │
│  │  Port interne : 5984 (pas exposé sur hôte)             │ │
│  │  Volume : /opt/services/couchdb/data                   │ │
│  │  Config : /opt/services/couchdb/etc/local.d/           │ │
│  └──────────────────────────┬──────────────────────────────┘ │
│                             │ réseau Docker interne sese      │
│  ┌──────────────────────────▼──────────────────────────────┐ │
│  │  n8n (existant)                                         │ │
│  │  Workflow : CouchDB Changes Feed → /opt/.../vault/      │ │
│  └──────────────────────────┬──────────────────────────────┘ │
│                             │ filesystem                      │
│  ┌──────────────────────────▼──────────────────────────────┐ │
│  │  /opt/services/obsidian-vault/ (fichiers .md déchiffrés)│ │
│  │  ← lu par OpenClaw / LiteLLM                           │ │
│  └─────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────┘
        ▲                   ▲                    ▲
        │                   │                    │
[Obsidian Desktop    [Obsidian iOS]    [Obsidian Android]
 ewutelo/Windows]    (pas de VPN       (pas de VPN
 (pas de VPN requis)  requis)           requis)
```

### 4.2 Tableau des accès réseau

| Accès | Protocole | Endpoint | Notes |
|-------|-----------|----------|-------|
| Clients Obsidian → CouchDB | HTTPS (TLS Let's Encrypt) | `https://biki.ewutelo.cloud` | Public, auth required |
| Debug Fauxton (admin) | HTTPS (même URL) | `https://biki.ewutelo.cloud/_utils` | Authentifié par CouchDB |
| n8n → CouchDB | HTTP (réseau Docker interne) | `http://couchdb:5984` | Interne sese, pas exposé |
| OpenClaw → vault | Filesystem | `/opt/services/obsidian-vault/` | Accès direct, zéro latence |
| Uptime Kuma (IONOS) → CouchDB | HTTPS | `https://biki.ewutelo.cloud/_up` | Monitoring externe |
| Futur Nextcloud | WebDAV sortant depuis n8n | `https://nextcloud.example.com/` | Sens unique, backup only |

### 4.3 Vhost Caddy sur sese

Le nouveau vhost Caddy suit exactement le même pattern que les vhosts existants sur sese.

**Template Jinja2 à ajouter dans le playbook sese :**
```
biki.ewutelo.cloud {
    reverse_proxy couchdb:5984

    # CORS géré côté CouchDB (local.ini) — pas de doublon ici
    # Caddy gère uniquement le TLS et le reverse proxy

    log {
        output file /var/log/caddy/biki.ewutelo.cloud.log {
            roll_size 10mb
            roll_keep 5
        }
    }
}
```

> ⚠️ **Pas de headers CORS dans Caddy.** Les CORS sont configurés dans `local.ini` de CouchDB. Doubler la config CORS crée des conflits de headers (`Access-Control-Allow-Origin` dupliqué) qui brisent la synchronisation mobile.

---

## 5. Spécifications techniques

### 5.1 CouchDB — Configuration requise

**Image :** `couchdb:3.3.3` (version pinnée, pas `latest`)

**Variables d'environnement (secrets dans vault du playbook sese) :**
```
COUCHDB_USER     → vault_couchdb_user
COUCHDB_PASSWORD → vault_couchdb_password
```

**Génération du mot de passe :** `openssl rand -base64 32 | tr -d '='` — aucune restriction de caractères pour CouchDB.

**docker-compose.yml (à intégrer dans le playbook Ansible sese) :**
```yaml
---
services:
  couchdb:
    image: couchdb:3.3.3
    container_name: couchdb
    restart: unless-stopped
    environment:
      COUCHDB_USER: "{{ vault_couchdb_user }}"
      COUCHDB_PASSWORD: "{{ vault_couchdb_password }}"
    volumes:
      - /opt/services/couchdb/data:/opt/couchdb/data
      - /opt/services/couchdb/etc:/opt/couchdb/etc/local.d
    networks:
      - proxy-net          # rejoint le réseau Caddy existant sur sese
    deploy:
      resources:
        limits:
          memory: 512M
        reservations:
          memory: 128M

networks:
  proxy-net:
    external: true         # réseau Caddy déjà existant sur sese
```

> **Note :** CouchDB n'expose PAS de port sur l'hôte (`ports:` absent). Caddy l'atteint via le nom de conteneur `couchdb:5984` sur le réseau `proxy-net` — identique au pattern des autres services sur sese.

**Configuration `local.ini` (template Jinja2 `couchdb-local.ini.j2`) :**
```ini
[couchdb]
users_db_security_editable = true
max_document_size = 50000000

[chttpd]
require_valid_user = true
max_http_request_size = 4294967296
enable_cors = true

[chttpd_auth]
require_valid_user = true

[httpd]
WWW-Authenticate = Basic realm="couchdb"
enable_cors = true

[cors]
origins = app://obsidian.md,capacitor://localhost,http://localhost
credentials = true
headers = accept, authorization, content-type, origin, referer, cache-control, x-requested-with
methods = GET, PUT, POST, HEAD, DELETE, OPTIONS, PATCH
max_age = 3600
```

> ⚠️ **Piège CORS critique :** Pas d'espace après les virgules dans `origins`. `app://obsidian.md,capacitor://localhost` ✅ — `app://obsidian.md, capacitor://localhost` ❌ (sync mobile silencieusement cassée).

**Permissions volumes :** CouchDB utilise l'UID `5984`. Pré-créer les répertoires et chowner avant le premier démarrage :
```bash
mkdir -p /opt/services/couchdb/{data,etc}
chown -R 5984:5984 /opt/services/couchdb/
```
Cette tâche est dans le playbook Ansible avec `ansible.builtin.file` (idempotent).

### 5.2 Initialisation CouchDB — One-shot post-déploiement

Après le premier démarrage, les bases système doivent être créées. Tâche Ansible avec `creates:` pour garantir l'idempotence :

```yaml
- name: Initialize CouchDB system databases
  ansible.builtin.uri:
    url: "https://biki.ewutelo.cloud/{{ item }}"
    method: PUT
    user: "{{ vault_couchdb_user }}"
    password: "{{ vault_couchdb_password }}"
    force_basic_auth: true
    status_code: [201, 412]  # 412 = already exists, idempotent
  loop:
    - _users
    - _replicator
    - _global_changes
```

> `status_code: [201, 412]` : 412 "Precondition Failed" signifie que la base existe déjà — comportement normal et idempotent.

### 5.3 Configuration client Obsidian LiveSync

Dans le plugin Self-hosted LiveSync (Obsidian) :

```
URI du serveur        : https://biki.ewutelo.cloud
Base de données       : obsidian-vault
Utilisateur           : <vault_couchdb_user>
Mot de passe          : <vault_couchdb_password>
Chiffrement E2E       : activé (recommandé — le serveur ne voit que des blobs)
Passphrase E2E        : [séparée du mot de passe CouchDB — à conserver précieusement]
```

> ⚠️ **Deux secrets distincts :** Le mot de passe CouchDB (authentification réseau) et la passphrase E2E (déchiffrement des données) sont deux secrets indépendants. Perdre la passphrase E2E = données irrécupérables même avec un accès admin à CouchDB.

### 5.4 Workflow n8n — Export vers filesystem (UC-02)

**Déclencheur :** Schedule toutes les 5 minutes (ou webhook sur Changes Feed CouchDB si n8n le supporte).

**Endpoint CouchDB depuis n8n (réseau Docker interne) :**
```
http://couchdb:5984/obsidian-vault/_changes?since={{ last_seq }}&include_docs=true
```

**Logique du workflow :**
1. GET `_changes` depuis le dernier `last_seq` connu (stocké en variable statique n8n)
2. Pour chaque document modifié non supprimé :
   - Déchiffrer le contenu si E2E activé (nécessite la passphrase E2E dans les credentials n8n)
   - Écrire le fichier `.md` dans `/opt/services/obsidian-vault/`
3. Pour chaque document supprimé (`_deleted: true`) :
   - Supprimer le fichier `.md` correspondant
4. Mettre à jour `last_seq`
5. Si erreur 3 fois consécutives → notification Telegram (canal existant sur sese)

> **Note sur le chiffrement E2E :** Si E2E est activé dans LiveSync, les documents dans CouchDB sont des blobs chiffrés. Le workflow n8n doit implémenter le déchiffrement (bibliothèque crypto compatible LiveSync) pour produire des `.md` lisibles par OpenClaw. Alternative : désactiver E2E si le chiffrement au niveau HTTPS + auth CouchDB est jugé suffisant pour UC-02.

---

## 6. Secrets à ajouter

Ces secrets sont gérés dans le **vault du playbook sese** (pas dans le vault Seko-VPN IONOS, car sese est un playbook Ansible distinct).

| Secret | Contrainte | Génération |
|--------|-----------|------------|
| `vault_couchdb_user` | Alphanumérique, 8-16 chars | Manuel (ex: `obsidian`) |
| `vault_couchdb_password` | Minimum 32 chars, tous caractères OK | `openssl rand -base64 32 \| tr -d '='` |
| `vault_couchdb_e2e_passphrase` | Libre, mémoriser précieusement | `openssl rand -base64 48` |

> Le `vault_couchdb_e2e_passphrase` est documenté dans le vault pour traçabilité mais est configuré manuellement dans le plugin Obsidian — jamais envoyé au serveur CouchDB.

---

## 7. DNS — Enregistrement requis

Ajouter un enregistrement DNS A chez le registrar du domaine `ewutelo.cloud` :

```
biki.ewutelo.cloud.  IN  A  137.74.114.167
```

Caddy récupère automatiquement le certificat Let's Encrypt lors du premier démarrage.

---

## 8. Implémentation — Phases

### Phase 1 — CouchDB + vhost Caddy sur sese (J+0 à J+1)

**Objectif :** CouchDB opérationnel derrière Caddy, accessible sur `https://biki.ewutelo.cloud`.

**Tâches Ansible (playbook sese) :**

- [ ] Ajouter l'enregistrement DNS `biki.ewutelo.cloud → 137.74.114.167`
- [ ] Créer les répertoires `/opt/services/couchdb/{data,etc}` avec `chown 5984:5984`
- [ ] Ajouter le service `couchdb` dans le `docker-compose.yml` de sese (réseau `proxy-net`)
- [ ] Déployer le template `couchdb-local.ini.j2` dans `/opt/services/couchdb/etc/`
- [ ] Ajouter le vhost `biki.ewutelo.cloud` dans le `Caddyfile` de sese
- [ ] Démarrer le conteneur et vérifier les logs : `docker compose logs couchdb`
- [ ] Initialiser les bases système via `ansible.builtin.uri` (tâche idempotente)
- [ ] Vérifier l'accès : `curl https://biki.ewutelo.cloud/`
- [ ] Vérifier Fauxton (debug UI) : `https://biki.ewutelo.cloud/_utils`

**Critère de succès :**
```bash
curl https://biki.ewutelo.cloud/_up
# → {"status":"ok"}
curl -u admin:password https://biki.ewutelo.cloud/_all_dbs
# → ["_replicator","_users","_global_changes"]
```

### Phase 2 — Configuration Obsidian LiveSync desktop (J+1)

**Objectif :** Obsidian Desktop (`ewutelo`) synchronise.

**Tâches manuelles (plugin Obsidian) :**

- [ ] Installer le plugin "Self-hosted LiveSync" dans Obsidian
- [ ] Configurer l'URI `https://biki.ewutelo.cloud`, base `obsidian-vault`
- [ ] Activer le chiffrement E2E + saisir la passphrase
- [ ] Effectuer la première synchronisation initiale
- [ ] Vérifier dans Fauxton que la base `obsidian-vault` est créée

**Critère de succès :** Obsidian affiche "Synchronized" sans erreur. La base `obsidian-vault` apparaît dans `/_utils`.

### Phase 3 — Export filesystem pour OpenClaw (J+2 à J+3)

**Objectif :** OpenClaw a accès aux fichiers `.md` à jour.

**Tâches :**

- [ ] Créer `/opt/services/obsidian-vault/` sur sese (propriétaire : user n8n)
- [ ] Créer le workflow n8n "CouchDB Changes → Filesystem Export"
- [ ] Décider : E2E activé (déchiffrement dans n8n) ou E2E désactivé (`.md` en clair dans CouchDB)
- [ ] Tester l'export : créer une note dans Obsidian → vérifier apparition dans `/opt/services/obsidian-vault/`
- [ ] Configurer OpenClaw pour lire depuis ce répertoire

**Critère de succès :** Une note créée dans Obsidian est disponible pour OpenClaw en moins de 5 minutes.

### Phase 4 — Mobile iOS/Android (J+3 à J+4)

**Objectif :** Obsidian iOS/Android synchronise sans Tailscale.

**Tâches manuelles :**

- [ ] Installer Obsidian sur mobile
- [ ] Installer le plugin Self-hosted LiveSync
- [ ] Configurer URI `https://biki.ewutelo.cloud` + même passphrase E2E
- [ ] Tester la synchronisation bidirectionnelle mobile ↔ desktop

**Critère de succès :** Une note créée sur mobile apparaît sur desktop en moins de 30 secondes.

### Phase 5 — Nextcloud backup (Futur, date TBD)

**Objectif :** Les notes `.md` sont archivées dans Nextcloud.

**Tâches :**

- [ ] Déployer Nextcloud sur le futur VPS dédié
- [ ] Étendre le workflow n8n : `/opt/services/obsidian-vault/` → WebDAV Nextcloud
- [ ] Configurer la rétention dans Nextcloud (versions de fichiers, corbeille)

**Critère de succès :** Le répertoire Nextcloud est un mirror en lecture seule du vault, mis à jour toutes les heures.

---

## 9. Monitoring

### 9.1 Uptime Kuma (IONOS) — Health check CouchDB

Ajouter un monitor dans Uptime Kuma sur IONOS (déjà en place) :

```
Type     : HTTP(s) - Keyword
URL      : https://biki.ewutelo.cloud/_up
Mot-clé  : "ok"
Intervalle : 60 secondes
```

L'endpoint `/_up` est natif CouchDB 3.x et ne nécessite pas d'authentification.

### 9.2 Monit (si déployé sur sese)

Si le playbook sese inclut Monit, ajouter un check conteneur :

```
check program couchdb-health
    with path "/usr/local/bin/docker-healthcheck couchdb"
    if status != 0 for 3 cycles then alert
```

### 9.3 Alerte synchronisation (n8n)

Dans le workflow n8n "CouchDB Export" :
- Si `last_seq` n'a pas évolué depuis 24h ET que des modifications Obsidian ont eu lieu → notification Telegram sur le canal sese.

---

## 10. Risques et mitigations

| Risque | Probabilité | Impact | Mitigation |
|--------|-------------|--------|------------|
| CouchDB OOM sur sese | Faible | Élevé | `memory: 512M` dans `deploy.resources.limits`. Monitorer avec `docker stats` |
| Perte passphrase E2E | Faible | Critique | Stocker dans Vaultwarden. Documenter dans `vault_couchdb_e2e_passphrase` |
| CORS mal configuré → sync mobile cassée | Moyen | Élevé | Tester avant prod : `curl -v -H "Origin: app://obsidian.md" https://biki.ewutelo.cloud/` |
| Double CORS (Caddy + CouchDB) | Élevé si non anticipé | Élevé | CORS uniquement dans `local.ini` CouchDB. Rien dans le Caddyfile |
| Nextcloud sync concurrent (Phase 5) | Élevé si mal configuré | Élevé | n8n écrit vers Nextcloud en sens unique. Jamais configurer Nextcloud comme client LiveSync |
| Conflit de données Obsidian | Faible | Moyen | LiveSync gère les conflits simples. Conflits complexes : résolution manuelle dans Obsidian |
| CouchDB exposé sans auth | Impossible | Critique | `require_valid_user = true` dans `local.ini` + HTTPS obligatoire |
| Perte données CouchDB | Faible | Élevé | Inclure `/opt/services/couchdb/data` dans la politique de backup du playbook sese |

---

## 11. Ce qui N'est PAS dans ce périmètre

- ❌ Modification du playbook Seko-VPN IONOS (aucun nouveau rôle côté IONOS)
- ❌ Déploiement de Nextcloud (Phase 5, futur)
- ❌ SSO/Authelia sur CouchDB (V4 roadmap globale)
- ❌ Chiffrement at-rest du disque de sese (hors périmètre)
- ❌ Remplacement de Vaultwarden par Obsidian pour la gestion des secrets

---

## 12. Références

- [vrtmrz/obsidian-livesync — GitHub](https://github.com/vrtmrz/obsidian-livesync)
- [Setup own server — Documentation officielle LiveSync](https://github.com/vrtmrz/obsidian-livesync/blob/main/docs/setup_own_server.md)
- [CouchDB 3.x Documentation officielle](https://docs.couchdb.org/en/stable/)
- `docs/01-architecture.md` — Architecture Seko-VPN V3 (patterns Caddy, proxy-net)
- `docs/04-roles-reference.md` — Référence des rôles (patterns Ansible réutilisables)
- `docs/06-v4-roadmap.md` — Feuille de route V4
- `docs/07-rex-v3.1.md` — REX production (pièges DinD, Caddy, CORS)
- `CLAUDE.md` — Infrastructure multi-serveurs (`nodes_extra_records`, accès SSH sese)
