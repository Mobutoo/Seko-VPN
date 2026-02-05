# ✅ Checklist de Déploiement — VPN & Vault

_Format imprimable — Cocher chaque étape au fur et à mesure._

---

## Pré-déploiement

### Infrastructure
- [ ] Serveur Debian 12/13 provisionné avec IP publique
- [ ] Accès SSH root fonctionnel
- [ ] 2 Go RAM minimum disponibles
- [ ] 20 Go disque minimum disponibles

### DNS
- [ ] Enregistrement A : `hs.__________.___` → `___.___.___.___`
- [ ] Enregistrement A : `vault.__________.___` → `___.___.___.___`
- [ ] Enregistrement A : `portainer.__________.___` → `___.___.___.___`
- [ ] Propagation DNS vérifiée (`dig +short` renvoie la bonne IP)

### Machine locale
- [ ] Python 3.10+ installé
- [ ] Ansible 2.15+ installé
- [ ] Collections installées : `community.docker`, `community.general`, `ansible.posix`
- [ ] Paire de clés SSH ed25519 générée
- [ ] Clé publique copiée sur le serveur

### Configuration
- [ ] `vars.yml` : `server_ip` renseigné
- [ ] `vars.yml` : `system_user` choisi → **nom : _______________**
- [ ] `vars.yml` : `system_user_ssh_pubkey` collé
- [ ] `vars.yml` : 3 domaines renseignés
- [ ] `vars.yml` : `acme_email` renseigné
- [ ] `vault.yml` : `vault_system_user_password` généré
- [ ] `vault.yml` : `vault_vaultwarden_admin_token` généré
- [ ] `.vault_password` créé avec permissions 600
- [ ] `vault.yml` chiffré avec `ansible-vault encrypt`

---

## Déploiement

- [ ] `ansible all -m ping` → SUCCESS
- [ ] `ansible-playbook playbooks/site.yml --check` → pas d'erreur critique
- [ ] `ansible-playbook playbooks/site.yml` → terminé sans erreur
- [ ] Port SSH et utilisateur mis à jour dans `vars.yml`

---

## Vérification post-déploiement

### Connectivité
- [ ] SSH sur nouveau port fonctionnel : `ssh -p ____ ______@IP`
- [ ] `ansible-playbook playbooks/verify.yml` → tous les checks passent

### Services
- [ ] `https://hs.__________` → accessible (certificat SSL valide)
- [ ] `https://vault.__________` → accessible (certificat SSL valide)
- [ ] `https://portainer.__________` → accessible (certificat SSL valide)

### Sécurité
- [ ] Port 22 fermé (SSH ancien port)
- [ ] Connexion root SSH refusée
- [ ] Connexion par mot de passe refusée
- [ ] UFW actif (vérifier avec `ufw status`)
- [ ] Fail2Ban actif (vérifier avec `fail2ban-client status`)

---

## Configuration des services

### Headscale
- [ ] Utilisateur créé : `docker exec headscale headscale users create ___`
- [ ] Clé pré-auth générée
- [ ] Premier client connecté et vérifié

### Vaultwarden
- [ ] Premier compte créé sur `https://vault.___/`
- [ ] Interface admin testée sur `https://vault.___/admin`
- [ ] `vaultwarden_signups_allowed` passé à `false`
- [ ] Redéploiement Vaultwarden effectué

### Portainer
- [ ] Compte admin créé
- [ ] Tous les conteneurs visibles dans l'interface

---

## Post-installation

- [ ] Backup initial des données effectué
- [ ] Mot de passe Vault Ansible stocké en lieu sûr
- [ ] Token admin Vaultwarden stocké en lieu sûr
- [ ] Documentation lue par l'équipe
- [ ] `.gitignore` configuré (si versioning)

---

**Date du déploiement** : ___/___/______

**Déployé par** : ___________________________

**Signature** : ___________________________
