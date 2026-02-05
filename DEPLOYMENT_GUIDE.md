# Guide de Déploiement Complet

Ce guide détaille chaque étape pour déployer l'infrastructure VPN & Vault depuis zéro. Il est rédigé pour qu'une personne sans expérience préalable du projet puisse le suivre de A à Z.

---

## Sommaire

1. [Prérequis](#1-prérequis)
2. [Préparation du serveur](#2-préparation-du-serveur)
3. [Préparation de la machine locale](#3-préparation-de-la-machine-locale)
4. [Configuration des variables](#4-configuration-des-variables)
5. [Configuration des secrets](#5-configuration-des-secrets)
6. [Configuration DNS](#6-configuration-dns)
7. [Lancement du déploiement](#7-lancement-du-déploiement)
8. [Vérification post-déploiement](#8-vérification-post-déploiement)
9. [Configuration des services](#9-configuration-des-services)
10. [Tâches post-installation](#10-tâches-post-installation)

---

## 1. Prérequis

### Machine locale (celle depuis laquelle vous lancez Ansible)

| Composant | Version minimale | Commande de vérification |
|-----------|-----------------|-------------------------|
| Python | 3.10+ | `python3 --version` |
| Ansible | 2.15+ | `ansible --version` |
| SSH | Toute version | `ssh -V` |

### Serveur cible

| Composant | Requis |
|-----------|--------|
| OS | Debian 12 (Bookworm) ou Debian 13 (Trixie) |
| RAM | 2 Go minimum, 4 Go recommandé |
| Disque | 20 Go minimum |
| Réseau | IP publique fixe |
| Accès | SSH root (pour le déploiement initial uniquement) |

### Noms de domaine

Vous avez besoin de **3 sous-domaines** pointant vers l'IP publique de votre serveur :

- `hs.votredomaine.com` → Headscale (VPN)
- `vault.votredomaine.com` → Vaultwarden (mots de passe)
- `portainer.votredomaine.com` → Portainer (supervision)

---

## 2. Préparation du serveur

### 2.1 Vérifier l'accès SSH

```bash
# Depuis votre machine locale
ssh root@IP_DU_SERVEUR
# Si ça fonctionne, vous êtes prêt. Tapez 'exit' pour revenir.
```

### 2.2 Générer une paire de clés SSH (si ce n'est pas déjà fait)

```bash
# Sur votre machine locale
ssh-keygen -t ed25519 -C "admin@monserveur"
# Résultat attendu : fichiers créés dans ~/.ssh/id_ed25519 et ~/.ssh/id_ed25519.pub
```

### 2.3 Copier la clé publique sur le serveur

```bash
ssh-copy-id root@IP_DU_SERVEUR
# Test : la connexion SSH ne doit plus demander de mot de passe
ssh root@IP_DU_SERVEUR
```

---

## 3. Préparation de la machine locale

### 3.1 Installer Ansible

```bash
# Ubuntu/Debian
sudo apt update && sudo apt install -y python3-pip
pip3 install ansible-core --break-system-packages

# macOS
brew install ansible

# Vérification
ansible --version
# Résultat attendu : ansible [core 2.15.x] ou supérieur
```

### 3.2 Installer les collections Ansible requises

```bash
ansible-galaxy collection install community.docker community.general ansible.posix
# Résultat attendu : "community.docker was installed successfully"
```

### 3.3 Extraire le projet

```bash
tar xzf vpn-vault-deploy.tar.gz
cd vpn-vault-deploy
```

---

## 4. Configuration des variables

### 4.1 Ouvrir le fichier de variables

```bash
nano inventory/group_vars/all/vars.yml
# ou avec l'éditeur de votre choix
```

### 4.2 Variables à modifier OBLIGATOIREMENT

| Variable | Description | Exemple |
|----------|-------------|---------|
| `server_ip` | IP publique du serveur | `51.15.123.45` |
| `system_user` | Nom de l'utilisateur système à créer | `srvadmin` |
| `system_user_ssh_pubkey` | Contenu de votre `~/.ssh/id_ed25519.pub` | `ssh-ed25519 AAAAC3...` |
| `domain_headscale` | Sous-domaine Headscale | `hs.mondomaine.fr` |
| `domain_vaultwarden` | Sous-domaine Vaultwarden | `vault.mondomaine.fr` |
| `domain_portainer` | Sous-domaine Portainer | `portainer.mondomaine.fr` |
| `acme_email` | Email pour Let's Encrypt | `admin@mondomaine.fr` |
| `headscale_base_domain` | Domaine Magic DNS | `vpn.mondomaine.fr` |

### 4.3 Récupérer votre clé publique SSH

```bash
cat ~/.ssh/id_ed25519.pub
# Copier TOUT le contenu (ssh-ed25519 AAAAC3... user@machine)
# Coller dans la variable system_user_ssh_pubkey du fichier vars.yml
```

---

## 5. Configuration des secrets

### 5.1 Générer des mots de passe forts

```bash
# Mot de passe utilisateur système
openssl rand -base64 24
# Exemple de résultat : xK9mP2vF8nQ4wR7bY1cL3hJ6

# Token admin Vaultwarden
openssl rand -base64 48
# Exemple de résultat : aB3cD4eF5gH6iJ7kL8mN9oP0qR1sT2uV3wX4yZ5...
```

### 5.2 Remplir le fichier de secrets

```bash
nano inventory/group_vars/all/vault.yml
```

Remplacer les valeurs `CHANGER_MOI_*` par vos mots de passe générés.

### 5.3 Créer le fichier de mot de passe Vault

```bash
# Ce mot de passe sert à chiffrer/déchiffrer vault.yml
# Choisissez quelque chose de mémorisable mais fort
echo "votre_mot_de_passe_vault_ansible" > .vault_password
chmod 600 .vault_password
```

### 5.4 Chiffrer le fichier de secrets

```bash
ansible-vault encrypt inventory/group_vars/all/vault.yml
# Résultat attendu : "Encryption successful"

# Vérification : le fichier doit commencer par $ANSIBLE_VAULT
head -1 inventory/group_vars/all/vault.yml
```

> **IMPORTANT** : Notez le mot de passe Vault quelque part de sûr. Sans lui, vous ne pourrez plus déchiffrer les secrets.

### 5.5 Pour modifier les secrets plus tard

```bash
ansible-vault edit inventory/group_vars/all/vault.yml
```

---

## 6. Configuration DNS

Créez ces 3 enregistrements DNS chez votre registrar :

| Type | Nom | Valeur | TTL |
|------|-----|--------|-----|
| A | `hs` | `IP_DU_SERVEUR` | 300 |
| A | `vault` | `IP_DU_SERVEUR` | 300 |
| A | `portainer` | `IP_DU_SERVEUR` | 300 |

### Vérification DNS (attendre la propagation, 5-30 min)

```bash
dig +short hs.mondomaine.fr
# Résultat attendu : l'IP de votre serveur

dig +short vault.mondomaine.fr
# Résultat attendu : l'IP de votre serveur

dig +short portainer.mondomaine.fr
# Résultat attendu : l'IP de votre serveur
```

> **⚠️ Ne lancez PAS le déploiement tant que le DNS ne résout pas correctement.** Caddy a besoin des DNS pour obtenir les certificats SSL.

---

## 7. Lancement du déploiement

### 7.1 Test de connexion

```bash
ansible all -m ping
# Résultat attendu :
# vpn-vault-server | SUCCESS => {
#     "ping": "pong"
# }
```

### 7.2 Dry-run (optionnel mais recommandé)

```bash
ansible-playbook playbooks/site.yml --check --diff
# Cela simule le déploiement sans rien modifier
```

### 7.3 Déploiement réel

```bash
ansible-playbook playbooks/site.yml
# Durée estimée : 5-15 minutes selon la connexion
```

### 7.4 Ce qui se passe pendant le déploiement

1. Mise à jour du système Debian
2. Création de l'utilisateur système (ex: `srvadmin`)
3. Durcissement SSH (changement de port, désactivation root)
4. Installation du firewall UFW et Fail2Ban
5. Installation de Docker
6. Déploiement de Caddy (reverse proxy + SSL)
7. Déploiement de Headscale (VPN)
8. Déploiement de Vaultwarden (mots de passe)
9. Déploiement de Portainer (supervision)

> **⚠️ IMPORTANT** : Après le déploiement, le port SSH a changé ! Mettez à jour `ssh_port` et `deploy_user` dans `inventory/group_vars/all/vars.yml` :
> ```yaml
> ssh_port: 2222          # ← nouveau port
> deploy_user: "srvadmin"  # ← votre utilisateur système
> ```

---

## 8. Vérification post-déploiement

### 8.1 Tester la connexion SSH avec le nouveau port

```bash
ssh -p 2222 srvadmin@IP_DU_SERVEUR
# Doit fonctionner sans mot de passe (clé SSH)
```

### 8.2 Lancer le playbook de vérification

Mettez d'abord à jour l'inventaire avec le nouveau port et utilisateur, puis :

```bash
ansible-playbook playbooks/verify.yml
```

### 8.3 Vérifications manuelles

```bash
# Tester Headscale
curl -s https://hs.mondomaine.fr/health | jq .
# Résultat attendu : réponse JSON

# Tester Vaultwarden
curl -sI https://vault.mondomaine.fr
# Résultat attendu : HTTP/2 200

# Tester Portainer
curl -sI https://portainer.mondomaine.fr
# Résultat attendu : HTTP/2 200

# Vérifier les certificats SSL
echo | openssl s_client -connect vault.mondomaine.fr:443 2>/dev/null | openssl x509 -noout -dates
# Résultat attendu : dates de validité du certificat Let's Encrypt
```

---

## 9. Configuration des services

### 9.1 Headscale - Créer un utilisateur et enregistrer des machines

```bash
# Se connecter au serveur
ssh -p 2222 srvadmin@IP_DU_SERVEUR

# Créer un utilisateur Headscale (namespace)
docker exec headscale headscale users create mon-utilisateur

# Générer une clé d'authentification (préauthkey)
docker exec headscale headscale preauthkeys create \
  --user mon-utilisateur \
  --reusable \
  --expiration 24h
# Résultat : une clé comme "randomstringdecaracteres"
```

### 9.2 Connecter un client au VPN

Sur la machine client, installer Tailscale puis :

```bash
# Linux
tailscale up --login-server https://hs.mondomaine.fr --authkey LA_CLE_GENEREE

# Vérifier
tailscale status
```

### 9.3 Vaultwarden - Créer le premier compte

1. Ouvrir `https://vault.mondomaine.fr` dans un navigateur
2. Cliquer "Créer un compte"
3. Remplir email, nom, mot de passe maître
4. Se connecter

### 9.4 Vaultwarden - Interface admin

1. Ouvrir `https://vault.mondomaine.fr/admin`
2. Entrer le token admin (celui de `vault_vaultwarden_admin_token`)
3. Configurer les paramètres selon vos besoins

### 9.5 Portainer - Configuration initiale

1. Ouvrir `https://portainer.mondomaine.fr`
2. Créer le compte administrateur (mot de passe fort !)
3. Sélectionner "Docker" comme environnement local

---

## 10. Tâches post-installation

### 10.1 Désactiver les inscriptions Vaultwarden

Une fois vos comptes créés, modifier `vars.yml` :

```yaml
vaultwarden_signups_allowed: false
```

Puis relancer :

```bash
ansible-playbook playbooks/site.yml --tags vaultwarden
```

### 10.2 Sauvegarder les données

Les données critiques se trouvent dans :

| Service | Chemin | Contenu |
|---------|--------|---------|
| Vaultwarden | `/opt/services/vaultwarden/data/` | Base de données des mots de passe |
| Headscale | `/opt/services/headscale/data/` | Base de données du VPN, clés |
| Caddy | `/opt/services/caddy/data/` | Certificats SSL |
| Portainer | `/opt/services/portainer/data/` | Configuration Portainer |

### 10.3 Mise à jour des images Docker

Pour mettre à jour un service :

```bash
# Exemple : mettre à jour Vaultwarden
# 1. Modifier la version dans vars.yml
# 2. Relancer le rôle
ansible-playbook playbooks/site.yml --tags vaultwarden
```

### 10.4 Fichier .gitignore recommandé

```bash
# Ne pas commiter dans Git :
.vault_password
*.retry
inventory/group_vars/all/vault.yml  # si non chiffré
```

---

## Résumé des ports

| Port | Protocole | Service | Exposition |
|------|-----------|---------|------------|
| 2222 (custom) | TCP | SSH | Public (protégé Fail2Ban) |
| 80 | TCP | HTTP → HTTPS | Public (redirect) |
| 443 | TCP/UDP | HTTPS + HTTP/3 | Public |
| 3478 | UDP | STUN/DERP | Public |
| 9000 | TCP | Portainer | Interne (via Caddy) |
| 8080 | TCP | Headscale | Interne (via Caddy) |
| 80 (VW) | TCP | Vaultwarden | Interne (via Caddy) |
