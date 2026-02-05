# 🔐 VPN & Vault - Déploiement Ansible

Déploiement automatisé d'une infrastructure **Headscale** (VPN WireGuard) + **Vaultwarden** (gestionnaire de mots de passe) + **Portainer** (supervision Docker) sur Debian 13, avec sécurité renforcée et certificats SSL automatiques.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    INTERNET                              │
│                                                          │
│   hs.domain.com   vault.domain.com   portainer.domain   │
│        │                │                  │             │
│        └────────────────┼──────────────────┘             │
│                         │                                │
│              ┌──────────▼──────────┐                     │
│              │   Caddy (HTTPS)     │  ← SSL auto         │
│              │   Port 80/443       │    Let's Encrypt     │
│              └──────────┬──────────┘                     │
│                         │ proxy-net (Docker)             │
│         ┌───────────────┼───────────────┐               │
│         │               │               │               │
│   ┌─────▼─────┐  ┌─────▼─────┐  ┌─────▼─────┐        │
│   │ Headscale │  │Vaultwarden│  │ Portainer  │        │
│   │ VPN Ctrl  │  │ Passwords │  │ Docker UI  │        │
│   └─────┬─────┘  └───────────┘  └───────────┘        │
│         │                                               │
│    Port 3478/UDP                                        │
│    (STUN/DERP)                                          │
│                                                          │
│   ┌────────────────────────────────────────────┐        │
│   │  Sécurité : UFW + Fail2Ban + SSH durci     │        │
│   │  Ports ouverts : SSH(custom), 80, 443, 3478│        │
│   └────────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────────┘
```

## Quick Start

### Prérequis

- **Machine locale** : Ansible 2.15+, Python 3.10+
- **Serveur cible** : Debian 12 ou 13, accès root SSH, IP publique
- **DNS** : 3 enregistrements A pointant vers le serveur
- **SSH** : Paire de clés ed25519 générée

### Installation en 5 minutes

```bash
# 1. Cloner ou extraire le projet
tar xzf vpn-vault-deploy.tar.gz
cd vpn-vault-deploy

# 2. Installer les dépendances Ansible
pip install ansible-core
ansible-galaxy collection install community.docker community.general ansible.posix

# 3. Configurer les variables
cp inventory/group_vars/all/vars.yml inventory/group_vars/all/vars.yml.bak
nano inventory/group_vars/all/vars.yml    # ← Modifier TOUTES les valeurs

# 4. Configurer les secrets
nano inventory/group_vars/all/vault.yml   # ← Mettre des vrais mots de passe
echo "mon_mot_de_passe_vault" > .vault_password
chmod 600 .vault_password
ansible-vault encrypt inventory/group_vars/all/vault.yml

# 5. Déployer
ansible-playbook playbooks/site.yml

# 6. Vérifier (après mise à jour du port SSH dans l'inventaire)
ansible-playbook playbooks/verify.yml
```

### Après le déploiement

1. **Headscale** : Créer un utilisateur et enregistrer des machines
2. **Vaultwarden** : Créer un compte sur `https://vault.domain.com`
3. **Portainer** : Définir le mot de passe admin sur `https://portainer.domain.com`
4. **Sécurité** : Passer `vaultwarden_signups_allowed: false` dans vars.yml

➡️ Voir [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) pour le guide complet.

## Structure du projet

```
vpn-vault-deploy/
├── ansible.cfg                    # Configuration Ansible
├── inventory/
│   ├── hosts.yml                  # Inventaire des serveurs
│   └── group_vars/all/
│       ├── vars.yml               # Variables (à personnaliser)
│       └── vault.yml              # Secrets (à chiffrer)
├── playbooks/
│   ├── site.yml                   # Playbook principal
│   └── verify.yml                 # Vérification post-déploiement
├── roles/
│   ├── common/                    # Système de base + utilisateur
│   ├── security/                  # UFW + Fail2Ban + sysctl
│   ├── docker/                    # Docker CE + Compose
│   ├── caddy/                     # Reverse proxy SSL
│   ├── headscale/                 # Serveur VPN
│   ├── vaultwarden/               # Gestionnaire de mots de passe
│   └── portainer/                 # Supervision Docker
├── README.md
├── DEPLOYMENT_GUIDE.md
├── CHECKLIST.md
└── TROUBLESHOOTING.md
```

## Tags disponibles

```bash
ansible-playbook playbooks/site.yml --tags common      # Système de base uniquement
ansible-playbook playbooks/site.yml --tags security     # Firewall et sécurité
ansible-playbook playbooks/site.yml --tags docker       # Docker uniquement
ansible-playbook playbooks/site.yml --tags caddy        # Reverse proxy
ansible-playbook playbooks/site.yml --tags headscale    # VPN Headscale
ansible-playbook playbooks/site.yml --tags vaultwarden  # Vaultwarden
ansible-playbook playbooks/site.yml --tags portainer    # Portainer
```

## Sécurité

- ✅ SSH : clé uniquement, port personnalisé, root désactivé
- ✅ Firewall UFW : politique deny par défaut
- ✅ Fail2Ban : protection brute-force SSH
- ✅ SSL/TLS : certificats Let's Encrypt auto-renouvelés (Caddy)
- ✅ Docker : `no-new-privileges`, capabilities minimales
- ✅ Kernel : sysctl durci (anti-spoofing, SYN cookies)
- ✅ Headscale : serveurs DERP personnalisés (indépendant de Tailscale Inc)

## Licence

Usage interne.
