# ============================================================
# AUDIT DE COHÉRENCE : Erreurs historiques vs État actuel
# ============================================================
# Ce document trace chaque erreur rencontrée dans les 4 sessions
# de débogage et vérifie si elle a été corrigée dans le playbook
# actuel, ET si elle a été généralisée en best practice.
# ============================================================

## LÉGENDE
# ✅ = Corrigé ET généralisé en best practice
# ⚠️  = Corrigé pour le composant touché, mais PAS généralisé
# ❌ = PAS corrigé - l'erreur est encore présente

---

## ERREUR 1 : cap_drop: ALL casse les conteneurs
# SESSION : 2 (ansible-headscale-deployment-fixes)
# CAUSE  : cap_drop: ALL empêchait les conteneurs d'écrire sur leur FS
# IMPACT : Headscale, Vaultwarden, Portainer crashaient
# ──────────────────────────────────────────────────────
# ÉTAT ACTUEL : ✅ CORRIGÉ ET GÉNÉRALISÉ
#   - Aucun docker-compose ne contient cap_drop: ALL
#   - Caddy, Headscale, Vaultwarden, Portainer : supprimé
#   - Headplane, Zerobyte : jamais eu
#   Grep résultat : 0 occurrences de cap_drop dans le projet

---

## ERREUR 2 : Headscale 0.23 → 0.26 format config incompatible
# SESSION : 2
# CAUSE  : La config Headscale v0.23 ne matchait pas le format v0.26
# IMPACT : Container refusait de démarrer
# ──────────────────────────────────────────────────────
# ÉTAT ACTUEL : ✅ CORRIGÉ
#   - headscale_version: "0.26.0" dans vars.yml
#   - config.yaml.j2 réécrite depuis le config-example.yaml officiel v0.26
#   - tmpfs /var/run/headscale ajouté au compose

---

## ERREUR 3 : tmpfs manquant pour Headscale
# SESSION : 2
# CAUSE  : Headscale 0.26 distroless nécessite tmpfs /var/run/headscale
# IMPACT : Le conteneur crashait au démarrage
# ──────────────────────────────────────────────────────
# ÉTAT ACTUEL : ⚠️ CORRIGÉ MAIS PAS COMPLÈTEMENT GÉNÉRALISÉ
#   - headscale standalone compose : ✅ tmpfs présent
#   - headplane compose (headscale service) : ✅ tmpfs présent
#   BEST PRACTICE : les deux composes contenant headscale ont le tmpfs
#   Mais ATTENTION : quand headplane gère headscale, le compose standalone
#   est désactivé. Les deux copies sont synchronisées → OK.

---

## ERREUR 4 : Vaultwarden LOG_FILE causait un crash
# SESSION : 2
# CAUSE  : LOG_FILE: "/data/vaultwarden.log" + cap_drop: ALL = pas d'écriture
# IMPACT : Container en crash loop
# ──────────────────────────────────────────────────────
# ÉTAT ACTUEL : ✅ CORRIGÉ
#   - LOG_FILE supprimé, logging vers stdout uniquement
#   - ROCKET_TLS supprimé (SSL géré par Caddy, pas Rocket)
#   - cap_drop: ALL supprimé

---

## ERREUR 5 : Portainer docker socket en :ro
# SESSION : 2
# CAUSE  : /var/run/docker.sock:/var/run/docker.sock:ro bloquait la gestion
# IMPACT : "Failed loading environment" dans Portainer
# ──────────────────────────────────────────────────────
# ÉTAT ACTUEL : ✅ CORRIGÉ
#   - Socket monté sans :ro (lecture-écriture)
#   Grep: /var/run/docker.sock:/var/run/docker.sock (pas de :ro)

---

## ERREUR 6 : Headplane healthcheck avec ansible.builtin.uri sur port non exposé
# SESSION : 3 (headplane-healthcheck-fix)
# CAUSE  : Port 3000 en "expose" (inter-conteneur) pas en "ports" (host)
#          ansible.builtin.uri essayait http://localhost:3000/admin → timeout
# IMPACT : Le playbook bloquait à l'attente du healthcheck
# ──────────────────────────────────────────────────────
# ÉTAT ACTUEL : ✅ CORRIGÉ ET GÉNÉRALISÉ
#   - Headplane : docker inspect (pas de port exposé, image distroless)
#   - Zerobyte  : docker inspect (même pattern, pas de port exposé)
#   - Headscale : docker exec headscale version (binaire disponible)
#   - Vaultwarden : ansible.builtin.uri sur localhost:8280 (port exposé ✓)
#   BEST PRACTICE : adapter le healthcheck selon l'image
#     - Distroless → docker inspect -f '{{.State.Running}}'
#     - Avec binaire → docker exec <cmd>
#     - Port exposé host → ansible.builtin.uri

---

## ERREUR 7 : Headplane docker exec binaire inexistant (distroless)
# SESSION : 4 (headplane-healthcheck-docker-integration-fix)
# CAUSE  : Image ghcr.io/tale/headplane:latest est distroless (pas de shell)
#          /bin/hp_healthcheck n'existe pas dans l'image
# IMPACT : OCI runtime exec failed: stat /bin/hp_healthcheck: no such file
# ──────────────────────────────────────────────────────
# ÉTAT ACTUEL : ✅ CORRIGÉ
#   - Remplacé par docker inspect -f '{{.State.Running}}'
#   - Pas de docker exec dans une image distroless

---

## ERREUR 8 : Headplane Docker integration cassée (label + même compose)
# SESSION : 4
# CAUSE  : Headplane ne trouvait pas Headscale via Docker API car :
#          1. Pas dans le même compose project
#          2. Pas de label me.tale.headplane.target sur le conteneur headscale
# IMPACT : "Could not request available Docker containers" dans les logs
# ──────────────────────────────────────────────────────
# ÉTAT ACTUEL : ✅ CORRIGÉ
#   - Headscale inclus dans le compose Headplane (depends_on)
#   - Label me.tale.headplane.target: "headscale" ajouté
#   - Docker socket monté en :ro dans headplane

---

## ERREUR 9 : Chemins relatifs dans docker-compose + Ansible
# SESSION : 4
# CAUSE  : ./config, ./data dans les compose posent problème quand Ansible
#          les déploie depuis un working directory différent
# IMPACT : Volumes vides ou montés au mauvais endroit
# ──────────────────────────────────────────────────────
# ÉTAT ACTUEL : ⚠️ PARTIELLEMENT CORRIGÉ
#
#   Headplane compose : ✅ Chemins absolus ({{ headplane_data_path }}/...)
#   Zerobyte compose  : ✅ Chemins absolus
#
#   Headscale compose : ❌ ENCORE DES CHEMINS RELATIFS
#     - ./config:/etc/headscale:ro
#     - ./data:/var/lib/headscale
#
#   Caddy compose     : ❌ ENCORE DES CHEMINS RELATIFS
#     - ./Caddyfile:/etc/caddy/Caddyfile:ro
#     - ./data:/data
#     - ./config:/config
#
#   Vaultwarden compose : ❌ ENCORE DES CHEMINS RELATIFS
#     - ./data:/data
#
#   Portainer compose   : ❌ ENCORE DES CHEMINS RELATIFS
#     - ./data:/data
#
#   NOTE : Ça fonctionne TANT QUE project_src pointe vers le bon
#   répertoire (ce qui est le cas avec community.docker.docker_compose_v2).
#   Mais le pattern est FRAGILE. Les chemins absolus sont meilleurs.
#
#   → ACTION RECOMMANDÉE : Convertir tous les compose en chemins absolus.

---

## ERREUR 10 : SSH hardening en milieu de playbook = lockout
# SESSION : 2
# CAUSE  : Le rôle security changeait le port SSH et désactivait root
#          pendant le playbook, coupant la connexion Ansible
# IMPACT : Ansible perdait la connexion SSH en plein déploiement
# ──────────────────────────────────────────────────────
# ÉTAT ACTUEL : ✅ CORRIGÉ ET GÉNÉRALISÉ
#   - harden-ssh.yml séparé du site.yml
#   - site.yml ne touche PAS à SSH (root, port 22)
#   - Le durcissement est la dernière étape MANUELLE
#   - Le firewall autorise le port 22 pendant le déploiement initial

---

## ERREUR 11 : Ownership system_user sur les données Docker
# SESSION : 2
# CAUSE  : Les données headscale/vaultwarden étaient en owner: system_user
#          mais les conteneurs tournent en root
# IMPACT : Erreurs de permissions au démarrage
# ──────────────────────────────────────────────────────
# ÉTAT ACTUEL : ✅ CORRIGÉ ET GÉNÉRALISÉ
#   - Tous les répertoires de données sont en owner: root, group: root
#   - Cohérent à travers TOUS les rôles (grep vérifié)

---

## ERREUR 12 : Caddy - répertoire de logs non créé
# SESSION : transversal (Caddyfile écrit dans /data/logs/*.log)
# CAUSE  : Le Caddyfile référence /data/logs/ mais ce répertoire
#          n'est PAS créé explicitement dans le rôle Caddy
# ──────────────────────────────────────────────────────
# ÉTAT ACTUEL : ⚠️ RISQUE POTENTIEL
#   - Caddy crée automatiquement /data/logs au premier write
#   - MAIS si les permissions sont restrictives, ça peut échouer
#   → ACTION RECOMMANDÉE : Ajouter {{ caddy_data_path }}/data/logs
#     dans la liste des répertoires créés par le rôle Caddy.

---

## ERREUR 13 : Vaultwarden healthcheck utilise curl (absent en alpine)
# SESSION : 1 (version initiale)
# CAUSE  : healthcheck: test: ["CMD", "curl", "-f", ...] mais l'image
#          alpine n'a pas curl installé par défaut
# ──────────────────────────────────────────────────────
# ÉTAT ACTUEL : ✅ CORRIGÉ
#   - Le healthcheck Docker a été supprimé du compose
#   - Remplacé par ansible.builtin.uri sur localhost:8280 (port exposé)
#   - Vaultwarden expose 127.0.0.1:8280:80 donc l'URI fonctionne

---

## ERREUR 14 (POTENTIELLE) : Headscale config.yaml en :ro empêche modifications
# ÉTAT ACTUEL : ⚠️ INCOHÉRENCE DÉTECTÉE
#   - Headscale standalone compose : ./config:/etc/headscale:ro  (lecture seule)
#   - Headplane compose (headscale) : config monté en :ro aussi ✓
#   - MAIS Headplane compose monte aussi la config en RW pour modifier :
#     {{ headscale_data_path }}/config/config.yaml:/etc/headscale/config.yaml
#   → C'est correct car Headplane modifie via son propre mount,
#     pas via le mount du headscale service.

---

# ============================================================
# RÉSUMÉ DES ACTIONS CORRECTIVES RESTANTES
# ============================================================
#
# PRIORITÉ HAUTE (peut causer des erreurs) :
#  1. ❌ ERR9 : Convertir les chemins relatifs en absolus dans :
#     - roles/headscale/templates/docker-compose.yml.j2
#     - roles/caddy/templates/docker-compose.yml.j2
#     - roles/vaultwarden/templates/docker-compose.yml.j2
#     - roles/portainer/templates/docker-compose.yml.j2
#
# PRIORITÉ MOYENNE (robustesse) :
#  2. ⚠️ ERR12 : Créer {{ caddy_data_path }}/data/logs dans caddy/tasks
#
# PRIORITÉ BASSE (cosmétique) :
#  3. Les healthchecks sont adaptés par image → OK
#  4. Les ownership sont uniformes → OK
#
# ============================================================
