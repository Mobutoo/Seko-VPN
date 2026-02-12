# REX V3.1 — Correctifs post-deploiement production

> Retour d'experience sur les 11 problemes rencontres lors du premier deploiement en production (IONOS) et la mise en service de Headscale + Headplane. Ce document est organise **par theme** pour retrouver rapidement la solution a un probleme.

---

## Navigation rapide

| Theme | Problemes | Ou chercher |
|-------|-----------|-------------|
| [Pipeline CI/CD](#pipeline-cicd) | SSH, Vault, secrets | Deploiement echoue dans GitHub Actions |
| [Headscale (VPN)](#headscale-vpn) | DERP, domaines, crash | Headscale ne demarre pas ou crash-loop |
| [Headplane (UI)](#headplane-ui) | DNS page, read-only, timeout | L'interface web affiche des erreurs |
| [Tests Molecule](#tests-molecule) | Variables manquantes | Le pipeline CI echoue au stage Molecule |
| [Operations serveur](#operations-serveur) | CLI, restart, connexion VPN | Commandes utiles post-deploiement |

---

## Pipeline CI/CD

> Problemes rencontres lors du deploiement via GitHub Actions.

### SSH key path incoherent

**Tu vois :**
```
Load key "~/.ssh/deploy_key": error in libcrypto
Permission denied (publickey)
```

**Pourquoi :** La cle SSH etait ecrite sous un nom (`seko-vpn-deploy`) mais referencee sous un autre (`deploy_key`) dans le pipeline.

**Fix :** Verifier que le nom de la cle est identique dans **toutes** les etapes du pipeline : ecriture, deploy, verify, cleanup.

**Fichier :** `.github/workflows/ci-cd.yml`

---

### vault.yml absent en CI

**Tu vois :**
```
TASK [assert] fatal: FAILED!
msg: "Assertion failed: vault_system_user_password is defined"
```

**Pourquoi :** `vault.yml` etait dans `.gitignore`. Le `git checkout` en CI ne le recuperait pas.

**Fix :** Retirer `vault.yml` du `.gitignore`. Le fichier est chiffre AES256, il est **sur a versionner**. Le pipeline utilise le secret GitHub `VAULT_PASSWORD` pour le dechiffrer.

**A retenir :** Un fichier chiffre Ansible Vault ≠ un secret en clair. Il **doit** etre dans le repo.

---

### Vault password avec newline

**Tu vois :**
```
ERROR! Decryption failed on vault.yml
```

**Pourquoi :** `echo "$VAULT_PASS"` ajoute `\n` en fin de fichier → le mot de passe est invalide.

**Fix :** Toujours ecrire les secrets sans newline :
```bash
# Mauvais
echo "$VAULT_PASS" > /tmp/.vault-pass

# Bon
printenv VAULT_PASS | tr -d '\n' > /tmp/.vault-pass
```

---

## Headscale (VPN)

> Problemes lies au serveur VPN Headscale. La plupart causent un crash-loop du conteneur.

### Crash — "initial DERPMap is empty"

**Tu vois :**
```
FTL > error="initial DERPMap is empty, Headscale requires at least one entry"
```

**Pourquoi :** Headscale 0.26.0 exige au moins un serveur DERP. Mettre `urls: []` sans alternative → crash.

**Fix :** Activer le **DERP embarque** (le serveur fait lui-meme office de relais) :

```yaml
derp:
  server:
    enabled: true
    region_id: 999
    region_code: "seko"
    region_name: "Seko VPN Self-Hosted"
    stun_listen_addr: 0.0.0.0:3478
    private_key_path: /var/lib/headscale/derp_server_private.key
    automatically_add_embedded_derp_region: true
    ipv4: {{ server_ip }}
  urls: []
```

**A faire aussi :**
- Exposer le port STUN dans docker-compose : `ports: ["3478:3478/udp"]`
- Ouvrir le port dans UFW : `3478/udp`

**A retenir :** Pour un VPN 100% self-hosted (zero trafic via Tailscale Inc), il faut le DERP embarque + `urls: []`. Le DERP embarque reutilise la connexion HTTPS (port 443 via Caddy), seul le STUN (3478/UDP) est un port supplementaire.

---

### Crash — "server_url cannot use same domain as base_domain"

**Tu vois :**
```
error="server_url cannot use the same domain as base_domain
in a way that could make the DERP and headscale server unreachable"
```

**Pourquoi :** `server_url` (API publique) et `dns.base_domain` (Magic DNS interne) utilisaient le meme domaine. Headscale interdit ca quand le DERP embarque est actif.

**Fix :** Utiliser **deux variables distinctes** :

| Variable | Exemple | C'est quoi |
|----------|---------|------------|
| `domain_headscale` | `singa.ewutelo.cloud` | Domaine public de l'API Headscale (vhost Caddy) |
| `headscale_base_domain` | `na.ewutelo.cloud` | Suffixe Magic DNS interne (ex: `monpc.na.ewutelo.cloud`) |

**A retenir :** `base_domain` est purement interne au VPN. Il n'a **pas besoin** d'enregistrement DNS chez le registrar. `domain_headscale` est le domaine public qui necessite un enregistrement DNS A vers l'IP du serveur.

---

### Crash — DERP private key path vide

**Tu vois :**
```
error="failed to save private key to disk at path \"\": open : no such file or directory"
```

**Pourquoi :** Le DERP embarque a besoin d'un fichier pour sa cle privee, mais `private_key_path` n'etait pas defini.

**Fix :** Ajouter dans la section `derp.server` :
```yaml
private_key_path: /var/lib/headscale/derp_server_private.key
```

Ce chemin est dans le volume Docker persistant → la cle survit aux redemarrages.

---

## Headplane (UI)

> Problemes lies a l'interface web d'administration Headplane.

### Page DNS — "Cannot convert undefined or null to object"

**Tu vois :** La page DNS affiche `Cannot convert undefined or null to object` ou `Cannot read properties of undefined (reading 'map')`.

**Pourquoi :** Headplane lit **directement** le fichier `config.yaml` de Headscale pour afficher la page DNS. Si des champs sont absents, le JavaScript crash.

**Fix :** S'assurer que **tous** ces champs sont presents dans `config.yaml.j2` (meme vides) :

```yaml
dns:
  magic_dns: true
  base_domain: {{ headscale_base_domain }}
  override_local_dns: false
  nameservers:
    global:
      - 1.1.1.1
      - 8.8.8.8
    split: {}
  search_domains: []
  extra_records: []
```

---

### Config read-only — DNS non modifiable

**Tu vois :** `The Headscale configuration is read-only` dans l'UI.

**Pourquoi :** Deux causes combinees :
1. Le volume Headscale monte en `:ro` dans le docker-compose de Headplane
2. `config_strict: false` dans la config Headplane

**Fix :**
1. Monter en `:rw` : `{{ headscale_data_path }}/config/config.yaml:/etc/headscale/config.yaml:rw`
2. Mettre `config_strict: true` dans `roles/headplane/templates/config.yaml.j2`

---

### Timeout 408 — "Timed out waiting for Headscale API"

**Tu vois :**
```
Unknown Error 408
Timed out waiting for a response from the Headscale API
```

**Pourquoi :** Headplane garde sa connexion a l'API Headscale en cache. Si Headscale est redemarre ou recree, Headplane ne se reconnecte pas automatiquement.

**Fix :**
```bash
docker restart headplane
```

**A retenir :** Toujours redemarrer Headplane **apres** un restart de Headscale. L'ordre compte : Headscale d'abord (verifier qu'il est up), puis Headplane.

---

## Tests Molecule

> Problemes qui font echouer le stage Molecule en CI.

### Variable server_ip undefined

**Tu vois :**
```
Task failed: 'server_ip' is undefined
```

**Pourquoi :** Toute variable utilisee dans un template `.j2` doit exister en CI. Molecule ne charge pas `inventory/group_vars/`.

**Fix :** Ajouter la variable a **deux endroits** :
1. `roles/headscale/defaults/main.yml` : `server_ip: "127.0.0.1"` (fallback CI)
2. `roles/headscale/molecule/default/converge.yml` : meme valeur dans le bloc `vars:`

En production, `inventory/group_vars/all/vars.yml` (genere par le wizard) override avec l'IP reelle.

**Regle generale :** Nouvelle variable dans un template → ajouter dans `defaults/main.yml` + `converge.yml`.

---

## Operations serveur

> Commandes et procedures utiles apres le deploiement.

### Headscale CLI : --user attend un ID numerique

**Tu vois :**
```
Error: invalid argument "mobuone" for "-u, --user" flag
```

**Pourquoi :** Depuis Headscale 0.26.0, `--user` attend un **ID** (nombre), pas un nom.

**Fix :** Recuperer l'ID d'abord :
```bash
docker exec headscale headscale users list
# Reperer l'ID (ex: 1), puis :
docker exec headscale headscale preauthkeys create --user 1 --reusable --expiration 24h
```

---

### Connecter un client VPN

```bash
# 1. Creer un utilisateur (une seule fois)
docker exec headscale headscale users create mobuone

# 2. Generer une cle d'authentification
docker exec headscale headscale users list          # noter l'ID
docker exec headscale headscale preauthkeys create --user 1 --reusable --expiration 24h

# 3. Sur le client (Windows/Linux/macOS avec Tailscale installe)
tailscale login --login-server https://singa.ewutelo.cloud --authkey hskey-auth-XXXXX
```

Le client apparait dans Headplane (`https://seko.ewutelo.cloud`) et est joignable via Magic DNS : `nomdupc.na.ewutelo.cloud`.

---

## Resume des fichiers modifies (V3.1)

| Fichier | Modifications |
|---------|--------------|
| `.github/workflows/ci-cd.yml` | SSH key path, vault password `printenv`, suppression debug steps |
| `.gitignore` | Retrait de `vault.yml` |
| `inventory/group_vars/all/vault.yml` | Ajoute au repo (chiffre AES256) |
| `inventory/group_vars/all/vars.yml` | `headplane_version: "0.6.1"`, `domain_headscale: singa`, `headscale_base_domain: na` |
| `roles/headscale/templates/config.yaml.j2` | DERP embarque, policy, DNS complet, base_domain separee |
| `roles/headscale/templates/docker-compose.yml.j2` | Port STUN 3478/UDP |
| `roles/headscale/templates/policy.json.j2` | Nouveau fichier (ACL allow all) |
| `roles/headscale/tasks/main.yml` | Tache deploiement policy ACL |
| `roles/headscale/defaults/main.yml` | `headscale_base_domain`, `server_ip` |
| `roles/headscale/molecule/default/converge.yml` | `headscale_base_domain`, `server_ip` |
| `roles/headplane/templates/docker-compose.yml.j2` | Volume `:ro` → `:rw` |
| `roles/headplane/templates/config.yaml.j2` | `config_strict: true` |
| `roles/security/tasks/main.yml` | Regles UFW WireGuard (41641/UDP) + STUN (3478/UDP) |

---

## Architecture reseau V3.1

```
Client HTTPS --> Caddy :443 --> Conteneur backend
                    |
                    |-- singa.ewutelo.cloud   -> headscale:8080 (API + DERP)
                    |-- seko.ewutelo.cloud    -> headplane:3000 (Admin UI)
                    |-- fongola.ewutelo.cloud -> vaultwarden:80
                    |-- pao.ewutelo.cloud     -> portainer:9000
                    |-- buku.ewutelo.cloud    -> zerobyte:4096
                    +-- misu.ewutelo.cloud    -> uptime-kuma:3001

STUN :3478/UDP -----> headscale (DERP embarque, relay sur notre serveur)
WireGuard :41641/UDP -> headscale (tunnel VPN chiffre)

Magic DNS interne : *.na.ewutelo.cloud (resolution au sein du VPN uniquement)
```
