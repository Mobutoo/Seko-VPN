# 🚀 Guide de déploiement pas-à-pas

> Ce guide te prend par la main du début à la fin. Chaque étape est expliquée. En cas d'erreur, consulte le [Dépannage](05-troubleshooting.md).

---

## Prérequis

Avant de commencer, vérifie que tu as :

**Sur ta machine locale :**
- [ ] Python 3.11+ installé (`python3 --version`)
- [ ] Git installé (`git --version`)
- [ ] Une clé SSH Ed25519 (`ls ~/.ssh/id_ed25519.pub`)
- [ ] Si pas de clé SSH : `ssh-keygen -t ed25519 -C "ton-email@example.com"`

**Sur l'hébergeur :**
- [ ] Un VPS Debian 12 ou 13 provisionné (ex: Hetzner CX22)
- [ ] L'IP du VPS notée
- [ ] L'accès root par SSH fonctionnel
- [ ] Un nom de domaine avec accès au panneau DNS

---

## Vue d'ensemble du workflow

```
Étape 1 : Cloner le repo
    │
Étape 2 : wizard.sh → Configure tout (vars.yml + vault.yml + hosts.yml)
    │
Étape 3 : Créer les 6 enregistrements DNS
    │
Étape 4 : bootstrap-vps.sh → Prépare le VPS (utilisateur + SSH + sudo)
    │
Étape 5 : site.yml → Déploie les 14 rôles
    │
Étape 6 : Vérification (Uptime Kuma + Telegram)
    │
Étape 7 : harden-ssh.yml → Durcit SSH (désactive root, change port)
    │
    ▼
Production ✅
```

---

## Étape 1 — Cloner le projet

```bash
git clone https://github.com/ton-user/seko-vpn.git
cd seko-vpn
```

### Installer l'environnement de développement local

```bash
# Installe Python venv, Molecule, ansible-lint, collections Ansible
./scripts/setup-ci.sh
```

> **💡 Qu'est-ce que `setup-ci.sh` fait ?** Il crée un environnement Python isolé (`.venv/`) et y installe toutes les dépendances : Ansible, Molecule, ansible-lint, yamllint, et les collections Ansible requises (comme `community.docker`).

---

## Étape 2 — Configurer avec le wizard

Le wizard est un script interactif qui te pose 10 questions et génère automatiquement les 3 fichiers de configuration.

```bash
./scripts/wizard.sh
```

### Les questions posées

| # | Question | Exemple de réponse | Valeur par défaut |
|---|----------|-------------------|-------------------|
| 1 | IP du VPS | `203.0.113.10` | (obligatoire) |
| 2 | Nom d'utilisateur système | `srvadmin` | `srvadmin` |
| 3 | Chemin clé SSH publique | `~/.ssh/id_ed25519.pub` | `~/.ssh/id_ed25519.pub` |
| 4 | Nom de domaine principal | `mondomaine.fr` | (obligatoire) |
| 5-10 | Sous-domaines (6 services) | `hs`, `nga`, `vault`... | Valeurs par défaut intelligentes |
| 11 | Email ACME (Let's Encrypt) | `admin@mondomaine.fr` | `admin@<domaine>` |
| 12 | Port SSH custom | `2222` | `2222` |
| 13 | Token bot Telegram | (secret) | (obligatoire) |
| 14 | Chat ID Telegram | `123456789` | (obligatoire) |
| 15 | Nom du serveur | `seko-vpn-01` | `seko-vpn-01` |

### Fichiers générés

| Fichier | Contenu | Chiffré ? |
|---------|---------|-----------|
| `inventory/group_vars/all/vars.yml` | Variables publiques (domaines, versions, chemins) | Non |
| `inventory/group_vars/all/vault.yml` | Secrets (mots de passe, tokens, clés) | **Oui** (ansible-vault) |
| `inventory/hosts.yml` | IP et accès SSH du serveur | Non |

### Secrets générés automatiquement

Le wizard génère 5 secrets avec les bonnes contraintes :

```
✅ Mot de passe utilisateur    → base64, 24 chars
✅ Token admin Vaultwarden     → base64, 32 chars
✅ Cookie secret Headplane     → exactement 32 chars
✅ App secret Zerobyte          → hex, exactement 64 chars
✅ Mot de passe Monit           → alphanumérique uniquement, 16 chars
```

> **⚠️ IMPORTANT :** Le wizard te demande de choisir un mot de passe pour `ansible-vault`. **Note-le bien !** Tu en auras besoin à chaque déploiement (option `--ask-vault-pass`).

> **💡 Comment obtenir un token Telegram ?** Envoie `/newbot` à `@BotFather` sur Telegram. Pour ton Chat ID, envoie `/start` à `@userinfobot`.

---

## Étape 3 — Configurer les DNS

Crée 6 enregistrements DNS de type A pointant vers l'IP de ton VPS :

```
hs.mondomaine.fr        A    203.0.113.10
nga.mondomaine.fr       A    203.0.113.10
vault.mondomaine.fr     A    203.0.113.10
portainer.mondomaine.fr A    203.0.113.10
zb.mondomaine.fr        A    203.0.113.10
status.mondomaine.fr    A    203.0.113.10
```

> **⏱️ Patience !** La propagation DNS peut prendre jusqu'à 24h (souvent 5-30 min). Tu peux vérifier avec : `dig hs.mondomaine.fr +short`

> **⚠️ Les DNS doivent être en place AVANT le déploiement !** Caddy a besoin que les domaines pointent vers le serveur pour obtenir les certificats SSL Let's Encrypt.

---

## Étape 4 — Préparer le VPS

Ce script se connecte en root à ton VPS et crée l'utilisateur qui sera utilisé par Ansible.

```bash
./scripts/bootstrap-vps.sh 203.0.113.10 srvadmin ~/.ssh/id_ed25519.pub
```

### Ce que le script fait

| # | Action | Détail |
|---|--------|--------|
| 1 | Met à jour le système | `apt update && apt upgrade` |
| 2 | Installe les paquets de base | `sudo`, `curl`, `wget`, `gnupg`, `ca-certificates` |
| 3 | Crée l'utilisateur | `useradd -m -s /bin/bash -G sudo srvadmin` |
| 4 | Configure sudo sans mot de passe | `/etc/sudoers.d/srvadmin` |
| 5 | Ajoute ta clé SSH | `~srvadmin/.ssh/authorized_keys` |
| 6 | Teste la connexion | SSH avec le nouvel utilisateur + `sudo whoami` |

### Ce que le script NE fait PAS

- ❌ Ne modifie PAS la configuration SSH
- ❌ Ne désactive PAS la connexion root
- ❌ Ne change PAS le port SSH
- ❌ N'installe PAS de firewall

> **💡 Pourquoi ?** Ces actions sont dangereuses si elles échouent. Elles sont faites en dernière étape (`harden-ssh.yml`) quand tout est validé.

### Résultat attendu

```
✅ Connexion établie
✅ Système mis à jour
✅ Paquets installés
✅ Utilisateur 'srvadmin' configuré
✅ Connexion SSH + sudo OK

  Utilisateur : srvadmin
  Mot de passe : aBcDeFgHiJkLmNoPqRsT1234
  ⚠️  Notez ce mot de passe ! Il ne sera plus affiché.
```

---

## Étape 5 — Déployer l'infrastructure

C'est LA commande principale. Elle exécute les 14 rôles dans l'ordre.

```bash
ansible-playbook playbooks/site.yml --ask-vault-pass
```

> **💡 `--ask-vault-pass`** : Ansible te demande le mot de passe que tu as choisi dans le wizard pour déchiffrer les secrets.

### Durée attendue

| VPS | Durée estimée |
|-----|--------------|
| Hetzner CX22 (2 vCPU, 4 Go) | ~10-15 min |
| VPS entrée de gamme (1 vCPU, 2 Go) | ~15-25 min |

### Déployer un seul rôle (en cas de mise à jour)

```bash
# Redéployer uniquement Uptime Kuma
ansible-playbook playbooks/site.yml --ask-vault-pass --tags uptime_kuma

# Redéployer uniquement le monitoring
ansible-playbook playbooks/site.yml --ask-vault-pass --tags monit

# Redéployer uniquement le hardening
ansible-playbook playbooks/site.yml --ask-vault-pass --tags hardening
```

### Résultat attendu

À la fin de l'exécution, Ansible affiche un résumé :

```
PLAY RECAP *********************************************************************
vps    : ok=89   changed=42   unreachable=0   failed=0   skipped=3   rescued=0
```

- `failed=0` → Tout s'est bien passé
- `changed=X` → X tâches ont modifié le système (normal au premier run)
- Au second run, `changed` devrait être 0 ou très faible (c'est l'**idempotence**)

---

## Étape 6 — Vérifier le déploiement

### Vérification automatisée

```bash
ansible-playbook playbooks/verify.yml --ask-vault-pass
```

### Vérification manuelle

| Test | Comment | Résultat attendu |
|------|---------|-----------------|
| Uptime Kuma | Ouvrir `https://status.mondomaine.fr` | Page de login Uptime Kuma |
| Vaultwarden | Ouvrir `https://vault.mondomaine.fr` | Page de login Bitwarden |
| Portainer | Ouvrir `https://portainer.mondomaine.fr` | Page de setup Portainer |
| Headscale | Ouvrir `https://hs.mondomaine.fr` | Réponse JSON du serveur VPN |
| Headplane | Ouvrir `https://nga.mondomaine.fr` | Interface admin VPN |
| Zerobyte | Ouvrir `https://zb.mondomaine.fr` | Interface de sauvegardes |
| Bot Telegram | Envoyer `/status` au bot | Résumé Monit de tous les services |
| Bot Telegram | Envoyer `/containers` | Liste des 8 conteneurs |
| SSH Monit | `ssh serveur` puis `sudo monit status` | État de tous les services |

> **⚠️ IMPORTANT :** Vérifie bien que TOUT fonctionne avant de passer à l'étape 7. L'étape 7 modifie SSH et pourrait te verrouiller si quelque chose ne va pas.

---

## Étape 7 — Durcir SSH (APRÈS validation)

**UNIQUEMENT quand tout fonctionne :**

```bash
ansible-playbook playbooks/harden-ssh.yml --ask-vault-pass
```

### Ce que harden-ssh.yml fait

| Action | Avant | Après |
|--------|-------|-------|
| Connexion root | ✅ Autorisée | ❌ Désactivée |
| Port SSH | 22 | 2222 (ou le port custom) |
| Auth par mot de passe | ✅ Autorisée | ❌ Désactivée (clé SSH uniquement) |

### Après le hardening SSH

La connexion SSH change :

```bash
# Avant
ssh srvadmin@203.0.113.10

# Après
ssh -p 2222 srvadmin@203.0.113.10
```

> **⚠️ ATTENTION :** Mets à jour `inventory/hosts.yml` avec le nouveau port SSH :
>
> ```yaml
> ansible_port: 2222  # Ancien : 22
> ```

### Tu es maintenant en production ! ✅

Le serveur se maintient seul :
- Les logs sont rotés automatiquement
- Les mises à jour de sécurité s'installent automatiquement
- Monit redémarre les services qui crashent
- Tu reçois les alertes sur Telegram
- Tu supervises via `/status` sur Telegram
- Le dashboard Uptime Kuma donne l'historique SLA

---

## Opérations courantes post-déploiement

### Modifier une variable

```bash
# Éditer vars.yml
vim inventory/group_vars/all/vars.yml

# Éditer un secret
ansible-vault edit inventory/group_vars/all/vault.yml

# Redéployer le rôle concerné
ansible-playbook playbooks/site.yml --ask-vault-pass --tags <role>
```

### Activer Grafana Alloy (quand un serveur Loki est disponible)

```bash
ansible-vault edit inventory/group_vars/all/vars.yml
# Modifier : alloy_loki_url: "http://loki.example.com:3100/loki/api/v1/push"

ansible-playbook playbooks/site.yml --tags alloy --ask-vault-pass
```

### Relancer le wizard (reset complet)

```bash
./scripts/wizard.sh
# Le wizard demande confirmation avant d'écraser les fichiers existants
```
