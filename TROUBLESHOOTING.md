# Dépannage — Problèmes courants et solutions

---

## 1. Problèmes de connexion SSH

### Je ne peux plus me connecter en SSH après le déploiement

**Cause** : Le port SSH a changé (22 → 2222 par défaut).

**Solution** :
```bash
ssh -p 2222 srvadmin@IP_DU_SERVEUR
```

Si ça ne fonctionne pas, vous avez accès via la **console VNC/KVM** de votre hébergeur :
```bash
# Sur le serveur via la console
sudo nano /etc/ssh/sshd_config
# Vérifier le port et l'utilisateur autorisé
sudo systemctl restart sshd
```

### "Permission denied (publickey)"

**Cause** : La clé SSH n'est pas reconnue.

**Vérifications** :
```bash
# 1. Vérifier que la clé existe
ls -la ~/.ssh/id_ed25519

# 2. Vérifier que c'est la bonne clé publique sur le serveur
# (via console VNC si SSH est inaccessible)
cat /home/srvadmin/.ssh/authorized_keys

# 3. Vérifier les permissions
# Sur le serveur :
chmod 700 /home/srvadmin/.ssh
chmod 600 /home/srvadmin/.ssh/authorized_keys
chown -R srvadmin:srvadmin /home/srvadmin/.ssh
```

---

## 2. Problèmes de certificats SSL

### "Acme error: too many certificates already issued"

**Cause** : Let's Encrypt a une limite de 5 certificats par semaine pour un même domaine.

**Solution** : Attendre une semaine, ou utiliser le staging Let's Encrypt pour les tests en ajoutant dans le Caddyfile global :
```
{
    acme_ca https://acme-staging-v02.api.letsencrypt.org/directory
}
```

### "TLS handshake error" / certificat auto-signé

**Cause** : Le DNS ne pointe pas encore vers le serveur, ou le port 80/443 est bloqué.

**Vérifications** :
```bash
# 1. Vérifier le DNS
dig +short vault.mondomaine.fr
# Doit retourner l'IP du serveur

# 2. Vérifier que les ports sont ouverts
sudo ufw status
# 80 et 443 doivent être ALLOW

# 3. Vérifier les logs Caddy
docker logs caddy --tail 50

# 4. Forcer le renouvellement
docker exec caddy caddy reload --config /etc/caddy/Caddyfile
```

---

## 3. Problèmes Docker

### "Cannot connect to the Docker daemon"

**Solution** :
```bash
sudo systemctl start docker
sudo systemctl status docker
# Si le service est en erreur :
sudo journalctl -u docker -n 50
```

### Un conteneur redémarre en boucle

```bash
# Voir les logs du conteneur
docker logs NOM_DU_CONTENEUR --tail 100

# Vérifier l'état
docker inspect NOM_DU_CONTENEUR | jq '.[0].State'

# Redémarrer proprement
cd /opt/services/NOM_DU_SERVICE
docker compose down && docker compose up -d
```

### "network proxy-net not found"

**Cause** : Le réseau Docker partagé n'existe pas.

**Solution** :
```bash
docker network create proxy-net
```

---

## 4. Problèmes Headscale

### "Cannot reach coordination server"

**Causes possibles** :
1. Le conteneur Headscale n'est pas démarré
2. Caddy ne proxy pas correctement
3. Le DNS ne pointe pas vers le serveur

**Vérifications** :
```bash
# 1. Conteneur en marche ?
docker ps | grep headscale

# 2. Headscale répond en interne ?
docker exec headscale headscale version

# 3. Caddy proxy correctement ?
docker logs caddy | grep headscale

# 4. Tester depuis l'extérieur
curl -v https://hs.mondomaine.fr/health
```

### Les clients ne peuvent pas se connecter entre eux (pas de trafic direct)

**Cause** : Les relais DERP ne fonctionnent pas.

**Vérifications** :
```bash
# Vérifier la config DERP
docker exec headscale cat /etc/headscale/config.yaml | grep -A 20 "derp:"

# Vérifier que le port STUN est ouvert
sudo ufw status | grep 3478
# Doit montrer : 3478/udp ALLOW

# Tester STUN depuis l'extérieur
# (nécessite le paquet stun-client)
stun hs.mondomaine.fr 3478
```

### "User not found" lors de la création de preauthkey

```bash
# Lister les utilisateurs existants
docker exec headscale headscale users list

# Créer l'utilisateur s'il n'existe pas
docker exec headscale headscale users create mon-utilisateur
```

---

## 5. Problèmes Vaultwarden

### Page blanche ou erreur 502

**Vérifications** :
```bash
# Conteneur en marche ?
docker ps | grep vaultwarden

# Logs
docker logs vaultwarden --tail 50

# Healthcheck
curl http://localhost:8280/alive
```

### Impossible d'accéder à /admin

**Cause** : Le token admin est incorrect ou vide.

**Solution** :
```bash
# Vérifier la variable d'environnement
docker exec vaultwarden env | grep ADMIN_TOKEN

# Si besoin, mettre à jour dans vault.yml, redéployer
ansible-playbook playbooks/site.yml --tags vaultwarden
```

### "Registration not allowed"

**Cause** : Les inscriptions ont été désactivées (`SIGNUPS_ALLOWED=false`).

**Solution** : Si vous devez créer un nouveau compte, modifier `vars.yml` :
```yaml
vaultwarden_signups_allowed: true
```
Redéployer, créer le compte, puis remettre à `false`.

---

## 6. Problèmes de firewall

### Un service est inaccessible depuis l'extérieur

```bash
# Vérifier UFW
sudo ufw status verbose

# Vérifier que le port est en écoute
sudo ss -tlnp | grep LISTEN

# Test rapide
sudo ufw allow PORT/PROTO comment "test temporaire"
# Ne pas oublier de supprimer après test :
sudo ufw delete allow PORT/PROTO
```

### Je me suis bloqué avec UFW

Si vous avez accès via **console VNC/KVM** de l'hébergeur :
```bash
sudo ufw disable
sudo ufw reset
# Reconfigurer depuis zéro
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 2222/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 3478/udp
sudo ufw enable
```

---

## 7. Problèmes Ansible

### "Using a SSH password instead of a key is not possible"

**Solution** : Ajouter `--ask-pass` ou configurer une clé SSH :
```bash
ansible-playbook playbooks/site.yml --ask-pass --ask-become-pass
```

### "Failed to decrypt vault.yml"

**Cause** : Le mot de passe Vault est incorrect ou le fichier `.vault_password` est manquant.

**Solution** :
```bash
# Vérifier que le fichier existe
cat .vault_password

# Tester le déchiffrement
ansible-vault view inventory/group_vars/all/vault.yml
```

### "Could not find role 'community.docker'"

```bash
ansible-galaxy collection install community.docker --force
```

---

## 8. Commandes utiles au quotidien

```bash
# État de tous les conteneurs
docker ps -a

# Redémarrer tous les services
for svc in caddy headscale vaultwarden portainer; do
  cd /opt/services/$svc && docker compose restart
done

# Espace disque des volumes Docker
docker system df

# Nettoyage Docker (images inutilisées)
docker system prune -a --volumes  # ⚠️ ATTENTION : supprime les données orphelines

# Logs en temps réel
docker logs -f NOM_DU_CONTENEUR

# Statut Fail2Ban
sudo fail2ban-client status sshd

# Débannir une IP
sudo fail2ban-client set sshd unbanip IP_A_DEBANNIR
```

---

## 9. Contacts et ressources

| Ressource | URL |
|-----------|-----|
| Documentation Headscale | https://headscale.net |
| Documentation Vaultwarden | https://github.com/dani-garcia/vaultwarden/wiki |
| Documentation Caddy | https://caddyserver.com/docs |
| Documentation Portainer | https://docs.portainer.io |
| Client Tailscale | https://tailscale.com/download |
