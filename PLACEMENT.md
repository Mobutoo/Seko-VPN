# ============================================================
# GUIDE DE PLACEMENT DES FICHIERS - v4 Monit + Zerobyte
# ============================================================

## FICHIERS NOUVEAUX (à créer)

### Monit - Templates manquants
monit-templates/check-container.sh.j2     → roles/monit/templates/check-container.sh.j2
monit-templates/conf.d/system.j2          → roles/monit/templates/conf.d/system.j2
monit-templates/conf.d/docker-containers.j2 → roles/monit/templates/conf.d/docker-containers.j2
monit-templates/conf.d/https-services.j2  → roles/monit/templates/conf.d/https-services.j2
monit-templates/conf.d/docker-daemon.j2   → roles/monit/templates/conf.d/docker-daemon.j2

### Zerobyte - Rôle complet (nouveau)
zerobyte-role/zerobyte-tasks-main.yml     → roles/zerobyte/tasks/main.yml
zerobyte-role/zerobyte-docker-compose.yml.j2 → roles/zerobyte/templates/docker-compose.yml.j2

## FICHIERS MODIFIÉS (à remplacer)

updated-configs/site.yml                  → playbooks/site.yml
updated-configs/vars.yml                  → inventory/group_vars/all/vars.yml
updated-configs/vault.yml                 → inventory/group_vars/all/vault.yml

## CHANGEMENTS RÉSUMÉS

### vars.yml
- vaultwarden_version: 1.35.2-alpine → 1.35.1-alpine (dernière release confirmée + SSO OIDC)
- zerobyte_version: v0.16 → v0.25 (dernière version stable)

### vault.yml
- AJOUT: vault_zerobyte_app_secret (requis depuis Zerobyte v0.23)

### site.yml
- AJOUT: rôle zerobyte (tag: zerobyte, backup)
- AJOUT: rôle monit (tag: monit, monitoring)
- AJOUT: assertions pré-déploiement pour Telegram, Zerobyte, domain_zerobyte
- MÀJ: résumé post-déploiement avec tous les services

## SECRETS À GÉNÉRER AVANT DÉPLOIEMENT

```bash
# Zerobyte app secret (64 chars hex)
openssl rand -hex 32

# Telegram bot token : créer via @BotFather
# Telegram chat ID : via https://api.telegram.org/bot<TOKEN>/getUpdates

# Monit password
openssl rand -base64 16
```

## ORDRE DE DÉPLOIEMENT

```bash
# 1. Déployer tout (services + monit + zerobyte)
ansible-playbook playbooks/site.yml

# 2. Ou par tags ciblés :
ansible-playbook playbooks/site.yml --tags zerobyte
ansible-playbook playbooks/site.yml --tags monit

# 3. DNS requis : A record pour zb.ewutelo.cloud

# 4. DERNIER : durcissement SSH
ansible-playbook playbooks/harden-ssh.yml
```
