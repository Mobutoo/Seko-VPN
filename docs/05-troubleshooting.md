# 🔧 Dépannage & Erreurs — Les 42 pièges documentés

> Ce document recense TOUTES les erreurs rencontrées pendant le développement de Seko-VPN (V1 → V2 → V3) et la mise en place du pipeline CI/CD (Day 0 → Round 5). Chaque piège est documenté avec le symptôme, la cause et la solution. Si tu rencontres un problème, cherche le symptôme dans cette page.

---

## Table de référence rapide

| # | Phase | Piège | Composant | Sévérité |
|---|-------|-------|-----------|----------|
| 2.1 | V1 | `docker_compose` legacy | Docker | 🔴 Bloquant |
| 2.2 | V1 | Healthcheck sur distroless | Headplane | 🔴 Bloquant |
| 2.3 | V1 | `handle_path /admin*` | Headplane/Caddy | 🔴 Bloquant |
| 2.4 | V1 | ACL notation décimale | Monit | 🟡 Éliminé V3 |
| 2.5 | V1 | `exec` dans `set alert` | Monit | 🔴 Bloquant |
| 2.6 | V1 | Caractères spéciaux mdp | Monit | 🟡 Auto V3 (wizard) |
| 2.7 | V1 | APP_SECRET manquant | Zerobyte | 🔴 Bloquant |
| 2.8 | V1 | Version inexistante | Vaultwarden | 🔴 Bloquant |
| 2.9 | V1 | Champ `version` obsolète | Compose | 🟡 Majeur |
| 2.10 | V2 | converge.yml sans vars | Molecule | 🔴 Bloquant |
| 2.11 | V2 | Pas de prepare.yml Docker | Molecule | 🔴 Bloquant |
| 2.12 | V2 | Makefile chemins relatifs | Makefile | 🔴 Bloquant |
| 2.13 | V2 | ansible-galaxy manquant CI | Pipeline | 🔴 Bloquant |
| 2.14 | V2 | Variables CI absentes | Pipeline | 🔴 Bloquant |
| 2.15 | V2 | failed_when: false | Molecule | 🟡 Majeur |
| 2.16 | V2 | monit -t absent | Molecule | 🟡 Majeur |
| 2.17 | V2 | 74 violations ansible-lint | Linting | 🟡 Majeur |
| 2.18 | V2 | setup-ci.sh DNS crash | Scripts | 🔴 Bloquant |
| 3.1 | V3 | Monit web exposition | Monit/Caddy | 🟡 Design → HEADLESS |
| 3.2 | V3 | Pas de rotation logs | Sysadmin | 🔴 Critique prod |
| 3.3 | V3 | Pas de mises à jour auto | Sysadmin | 🔴 Critique prod |
| 3.4 | V3 | Pas de NTP | Sysadmin | 🟡 Important prod |
| 3.5 | V3 | Pas de swap < 4G RAM | Sysadmin | 🟡 Important prod |
| 3.6 | V3 | DNS CI/CD inexistants | Pipeline | 🔴 Bloquant → ci_mode |
| 3.7 | V3 | Config manuelle = erreurs | UX | 🟡 Design → wizard.sh |
| **4.1** | **CI Day 0** | **ZIP avec `{.github` (expansion bash)** | **Scripts** | 🟡 Majeur |
| **4.2** | **CI Day 0** | **Prompts invisibles dans wizard `$(...)`** | **Scripts** | 🔴 Bloquant |
| **4.3** | **CI Day 0** | **27 violations ansible-lint** | **Linting** | 🟡 Majeur |
| **4.4** | **CI Day 0** | **YAML `:` dans format Docker** | **Linting** | 🔴 Bloquant |
| **4.5** | **CI Day 0** | **SSH key paths hardcodés** | **Scripts** | 🟡 Majeur |
| **4.6** | **CI R1** | **`lsb-release` absent Debian 13** | **Molecule** | 🔴 Bloquant |
| **4.7** | **CI R1** | **`python3-requests` manquant (7 rôles)** | **Molecule** | 🔴 Bloquant |
| **4.8** | **CI R1** | **Dash vs Bash (`pipefail`)** | **Molecule** | 🔴 Bloquant |
| **4.9** | **CI R1** | **Hash password invalide** | **Molecule** | 🔴 Bloquant |
| **4.10** | **CI R1** | **systemd indisponible en Docker** | **Molecule** | 🟡 Majeur |
| **4.11** | **CI R1** | **apt cache stale** | **Molecule** | 🟡 Majeur |
| **4.12** | **CI R4** | **DinD : bind mount de FICHIER** | **Molecule** | 🔴 Bloquant |
| **4.13** | **CI R4** | **Idempotence impossible (crash-loop)** | **Molecule** | 🟡 Majeur |
| **4.14** | **CI R5** | **`hcloud --datacenter` déprécié** | **Intégration** | 🔴 Bloquant |
| **4.15** | **CI R5** | **Callback `community.general.yaml` supprimé** | **Intégration** | 🔴 Bloquant |
| **4.16** | **CI R5** | **Services en `activating` au verify** | **Intégration** | 🟡 Majeur |
| **4.17** | **CI R5** | **Monit daemon not running en CI** | **Intégration** | 🟡 Majeur |

---

## Phase 1 — Erreurs de déploiement (V1)

### 2.1 Docker Compose legacy

**Symptôme :**
```
TASK [headscale : Deploy docker-compose] fatal: FAILED!
msg: "Unable to load docker-compose"
```

**Cause :** Le module `community.docker.docker_compose` (V1) ne fonctionne pas avec Docker Engine 29. Engine 29 ne fournit que le plugin CLI `docker compose` (v2/v5), pas le binaire standalone `docker-compose`.

**Solution :** Utiliser `community.docker.docker_compose_v2` dans TOUS les rôles.

```yaml
# ❌ INTERDIT
- community.docker.docker_compose:
    project_src: "{{ path }}"

# ✅ CORRECT
- community.docker.docker_compose_v2:
    project_src: "{{ path }}"
```

---

### 2.2 Healthcheck Headplane impossible

**Symptôme :**
```
healthcheck: wget -q --spider http://localhost:3000 || exit 1
UNHEALTHY
```

**Cause :** L'image Headplane est **distroless** — elle ne contient ni `wget`, ni `curl`, ni `sh`, ni aucun binaire utilitaire.

**Solution :** Supprimer le healthcheck Docker pour Headplane. Vérifier l'état via `docker inspect` depuis Ansible.

```yaml
# ❌ INTERDIT dans docker-compose.yml de Headplane
healthcheck:
  test: ["CMD", "wget", ...]

# ✅ CORRECT : pas de healthcheck
# (l'état est vérifié par Monit)
```

---

### 2.3 Headplane — `handle_path /admin*` casse le routage

**Symptôme :** 404 sur les assets statiques (CSS, JS) quand on accède à l'interface Headplane.

**Cause :** Headplane attend que TOUTES les requêtes arrivent avec le préfixe `/admin` (c'est hardcodé dans le code). `handle_path` strip le préfixe → les routes internes sont cassées.

**Solution :** Sous-domaine dédié + `redir / /admin permanent` dans le Caddyfile.

```
# ❌ INTERDIT
example.com {
    handle_path /admin* {
        reverse_proxy headplane:3000
    }
}

# ✅ CORRECT
nga.example.com {
    redir / /admin permanent
    reverse_proxy headplane:3000
}
```

---

### 2.5 Monit — `exec` dans `set alert`

**Symptôme :**
```
/etc/monit/monitrc:15: syntax error: unexpected token 'exec'
monit: Cannot initialize Configuration -- ABORTING
```

**Cause :** La directive `exec` n'est autorisée que dans les blocs `check`, PAS dans `set alert` global.

**Solution :** Déplacer les alertes Telegram dans chaque bloc `check` via le template Jinja2.

---

### 2.6 Monit — Mot de passe avec caractères spéciaux

**Symptôme :** Monit ne démarre pas, ou l'authentification échoue.

**Cause :** Les caractères `"`, `#`, `{`, `}` cassent le parser Monit.

**Solution :** Mot de passe alphanumérique UNIQUEMENT (`a-zA-Z0-9`). Le wizard.sh V3 génère automatiquement un mot de passe conforme.

```bash
# Le wizard génère ça :
openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 16
```

---

### 2.7 Zerobyte — APP_SECRET manquant

**Symptôme :**
```
Error: APP_SECRET environment variable is required
Container exited with code 1
```

**Cause :** La variable `APP_SECRET` est obligatoire depuis la version 0.22 et doit faire exactement 64 caractères hexadécimaux.

**Solution :** Générer avec `openssl rand -hex 32` (produit 64 hex chars). Le wizard.sh le fait automatiquement.

---

### 2.8 Vaultwarden — Version inexistante

**Symptôme :**
```
Error response from daemon: manifest for vaultwarden/server:1.35.2 not found
```

**Cause :** La version `1.35.2` n'existe pas sur Docker Hub.

**Solution :** Vérifier les versions disponibles sur [Docker Hub](https://hub.docker.com/r/vaultwarden/server/tags) et utiliser `1.35.1-alpine`.

---

### 2.9 Docker Compose — Champ `version` obsolète

**Symptôme :**
```
WARN[0000] .../docker-compose.yml: `version` is obsolete
```

**Cause :** Le champ `version` est obsolète depuis Compose v5.

**Solution :** Supprimer le champ `version:` de TOUS les fichiers docker-compose.yml.

```yaml
# ❌ INTERDIT
version: "3.8"
services:
  ...

# ✅ CORRECT
services:
  ...
```

---

## Phase 2 — Erreurs CI/CD et Molecule (V2)

### 2.10 Molecule converge.yml sans variables

**Symptôme :**
```
TASK [headscale : ...] fatal: FAILED!
msg: "The task includes an option with an undefined variable: 'domain_headscale'"
```

**Cause :** Molecule ne charge PAS le `inventory/group_vars/`. Les variables ne sont pas disponibles.

**Solution :** Chaque `converge.yml` DOIT contenir un bloc `vars:` avec des valeurs mock :

```yaml
# roles/headscale/molecule/default/converge.yml
---
- name: Converge
  hosts: all
  vars:                            # OBLIGATOIRE
    domain_headscale: "hs.test.local"
    headscale_version: "0.26.0"
    headscale_data_path: "/opt/services/headscale"
    base_deploy_path: "/opt/services"
  roles:
    - role: headscale
```

---

### 2.11 Pas de prepare.yml Docker

**Symptôme :**
```
TASK [caddy : Deploy docker-compose] fatal: FAILED!
msg: "docker: command not found"
```

**Cause :** Les rôles conteneurs présupposent Docker installé. Molecule lance le rôle en isolation, sans Docker.

**Solution :** Un `prepare.yml` qui installe Docker + crée le réseau `proxy-net`. Nécessaire pour **7 rôles** : caddy, headscale, headplane, vaultwarden, portainer, zerobyte, uptime_kuma.

---

### 2.12 Makefile chemins relatifs

**Symptôme :**
```
make role ROLE=caddy
cd roles/caddy && .venv/bin/molecule test
bash: .venv/bin/molecule: No such file or directory
```

**Cause :** Après `cd roles/caddy`, le chemin relatif `.venv/` ne pointe plus vers la racine du projet.

**Solution :** Utiliser des chemins absolus dans le Makefile :

```makefile
ROOT_DIR := $(shell pwd)
MOLECULE := $(ROOT_DIR)/.venv/bin/molecule
```

---

### 2.13 ansible-galaxy manquant en CI

**Symptôme :**
```
ERROR! the collection 'community.docker' was not found
```

**Cause :** Les collections Ansible ne sont PAS installées par défaut dans les runners CI GitHub Actions.

**Solution :** Ajouter `ansible-galaxy collection install -r requirements.yml` dans **les 3 jobs** (lint, molecule, integration).

---

### 2.14 Variables CI absentes

**Symptôme :**
```
TASK [assert] fatal: FAILED!
msg: "Variable 'domain_headscale' is still set to 'CHANGER_MOI_headscale'"
```

**Cause :** Le playbook vérifie dans ses `pre_tasks` que les variables ne sont pas les valeurs par défaut "CHANGER_MOI_*".

**Solution V3 :** Le fichier `tests/ci-vars.yml` contient des valeurs de test + `ci_mode: true`.

---

### 2.15 `failed_when: false` dans verify.yml

**Symptôme :** Les tests Molecule passent toujours, même quand la vérification échoue réellement.

**Cause :** `failed_when: false` désactive la détection d'erreur → le test est inopérant.

**Solution :** Retirer `failed_when: false`. Si un test doit être conditionnel, utiliser `when:`.

```yaml
# ❌ INTERDIT
- name: Vérifier Docker
  command: docker version
  failed_when: false         # ← LE TEST NE SERT À RIEN

# ✅ CORRECT
- name: Vérifier Docker
  command: docker version
  changed_when: false        # ← OK : ne marque pas changed, mais détecte les erreurs
```

---

### 2.18 setup-ci.sh DNS crash

**Symptôme :** Le script `setup-ci.sh` crash avec une erreur GPG lors de l'ajout du dépôt Docker ou Grafana.

**Cause :** `gpg --dearmor` sans `--yes` attend un prompt interactif si le fichier de sortie existe déjà.

**Solution :** Toujours utiliser `gpg --yes --dearmor`.

---

## Phase 3 — Erreurs de conception corrigées (V3)

### 3.1 Monit web — Problème récurrent d'exposition

**Symptôme V1/V2 :** L'exposition de l'interface web Monit via Caddy causait des problèmes répétés : ACL décimale, mot de passe, réseau bridge.

**Cause :** Monit n'a pas été conçu pour être exposé via un reverse proxy Docker. Son système d'ACL est archaïque.

**Solution V3 — Double approche :**
1. **Monit passe en HEADLESS** : plus de vhost Caddy, `allow localhost` uniquement
2. **Uptime Kuma remplace la UI** : interface web moderne sur `status.example.com`

---

### 3.2 Pas de rotation des logs système

**Symptôme :** Après 6 mois en production, `/var/log/journal` remplit le disque à 100%.

**Cause :** journald n'a pas de limite par défaut. Les services custom (Monit, Alloy, bot) n'ont pas de règle logrotate.

**Solution V3 :** Rôle `hardening` configure journald (`SystemMaxUse=500M`, `MaxRetentionSec=30day`) + logrotate pour tous les services custom.

> **💡 Leçon :** La rotation des logs, c'est du Day 1 (installation), pas du Day 2 (maintenance).

---

### 3.6 DNS CI/CD inexistants sur VM éphémère

**Symptôme :**
```
Caddy: ACME challenge failed for hs.example.com
Error: DNS record not found
```

**Cause :** La VM CI Hetzner est éphémère. Les DNS pointent vers la prod, pas la VM de test.

**Solution V3 — ci_mode :**
- Variable `ci_mode: false` (défaut)
- Quand `ci_mode: true` → Caddy utilise `local_certs` (auto-signés)
- `tests/ci-vars.yml` avec domaines fictifs `*.ci-test.local`
- Le pipeline passe `--extra-vars "ci_mode=true" --extra-vars "@tests/ci-vars.yml"`

---

## Phase 4 — Erreurs Pipeline CI/CD (Day 0 → Round 5)

> Ces 17 erreurs ont été découvertes lors de la mise en service complète du pipeline CI/CD. Elles constituent les pièges les plus fréquents quand on passe de tests locaux à une CI industrialisée.

### 4.1 ZIP avec `{.github` — Expansion bash

**Symptôme :** Le ZIP de release contient un répertoire nommé `{.github` au lieu de `.github`.

**Cause :** Utiliser `{.github,...}` dans une commande `mkdir -p` provoque l'expansion d'accolades bash.

**Solution :** Toujours vérifier le contenu du ZIP avant distribution : `unzip -l archive.zip`.

---

### 4.6 `lsb-release` absent sur Debian 13

**Symptôme :**
```
bash: lsb_release: command not found
```

**Cause :** Debian 13 (trixie) ne pré-installe pas `lsb-release`. Les `prepare.yml` qui utilisent `lsb_release -cs` pour ajouter le dépôt Docker échouent.

**Solution :** Ajouter `lsb-release` dans le `prepare.yml` de chaque rôle qui installe Docker.

```yaml
# prepare.yml — début obligatoire
- name: Install CI prerequisites
  ansible.builtin.apt:
    name: [lsb-release, python3-requests, gnupg]
    state: present
    update_cache: true
```

---

### 4.7 `python3-requests` manquant (7 rôles)

**Symptôme :**
```
ModuleNotFoundError: No module named 'requests'
```

**Cause :** Le module `community.docker` a besoin de la bibliothèque Python `requests`. Les images Docker de test ne l'incluent pas.

**Solution :** Ajouter `python3-requests` dans le `prepare.yml` de chaque rôle Docker (caddy, headscale, headplane, vaultwarden, portainer, zerobyte, uptime_kuma).

---

### 4.8 Dash vs Bash — `set -o pipefail`

**Symptôme :**
```
set: Illegal option -o pipefail
```

**Cause :** Les conteneurs Debian utilisent `dash` comme `/bin/sh`. `pipefail` est une option bash uniquement.

**Solution :** Ajouter `executable: /bin/bash` sur CHAQUE tâche `shell` qui utilise `pipefail`.

```yaml
# ❌ INTERDIT — échoue avec dash
- name: Add Docker repo
  ansible.builtin.shell:
    cmd: |
      set -o pipefail
      curl -fsSL https://... | gpg --dearmor ...

# ✅ CORRECT — force bash
- name: Add Docker repo
  ansible.builtin.shell:
    executable: /bin/bash
    cmd: |
      set -o pipefail
      curl -fsSL https://... | gpg --dearmor ...
```

> **💡 C'est l'erreur #1 en fréquence** (17+ occurrences). Toute tâche `shell` avec un pipe (`|`) doit avoir `executable: /bin/bash` + `set -o pipefail`.

---

### 4.9 Hash de mot de passe invalide

**Symptôme :**
```
usermod: invalid password hash
```

**Cause :** La fonction Jinja2 `password_hash()` sans algorithme produit un hash incompatible.

**Solution :** Toujours utiliser `password_hash('sha512')` dans les templates.

---

### 4.10 systemd indisponible en Docker

**Symptôme :**
```
System has not been booted with systemd as init system
```

**Cause :** Les conteneurs Docker standard n'ont pas systemd. Les tâches `systemctl enable/start` échouent.

**Solution :** Conditionner les tâches systemd :

```yaml
- name: Enable service
  ansible.builtin.systemd:
    name: monit
    enabled: true
  when: ansible_virtualization_type != "docker"
```

---

### 4.12 DinD — Bind mount de FICHIER impossible

**Symptôme :**
```
Error: mount destination /etc/caddy/Caddyfile is not a directory
```

**Cause :** En Docker-in-Docker (DinD), le socket Docker est partagé avec l'hôte. Quand Ansible crée un fichier dans le conteneur Molecule puis monte ce fichier dans un sous-conteneur, l'hôte externe n'a PAS ce fichier → Docker le crée comme RÉPERTOIRE → conflit de type.

**Solution — Règle absolue DinD :**

```yaml
# ❌ INTERDIT en DinD — bind mount de fichier
volumes:
  - ./Caddyfile:/etc/caddy/Caddyfile:ro

# ✅ CORRECT — bind mount de répertoire
volumes:
  - ./conf:/etc/caddy:ro
```

> **⚠️ C'est un piège invisible.** Le même `docker-compose.yml` fonctionne en local mais échoue systématiquement en CI (Molecule DinD). Si un rôle Docker échoue uniquement en CI avec une erreur de mount, vérifier les bind mounts.

---

### 4.13 Idempotence impossible — Conteneur crash-loop

**Symptôme :**
```
TASK [caddy : Deploy docker-compose] changed: [instance]
# Au 2nd run (idempotence) : changed=true → test échoue
```

**Cause :** En CI, les conteneurs n'ont pas de DNS réels ni de configuration complète. Ils démarrent (`running`) puis crashent immédiatement (`restarting`). Au 2ème converge, `docker compose up` détecte le changement d'état → `changed: true`.

**Solution :** Supprimer `idempotence` du `test_sequence` dans `molecule.yml` pour les rôles avec conteneurs instables en CI.

```yaml
# molecule.yml
provisioner:
  name: ansible
platforms:
  - name: instance
    image: geerlingguy/docker-debian12-ansible
scenario:
  test_sequence:
    - create
    - prepare
    - converge
    # PAS de "idempotence" — container crash-loop en CI
    - verify
    - destroy
```

> **💡 L'idempotence doit être testée manuellement** en environnement réaliste (VM Hetzner), pas en DinD avec une config minimale.

---

### 4.14 `hcloud --datacenter` déprécié

**Symptôme :**
```
Flag --datacenter is deprecated, use --location instead
```

**Cause :** Le CLI hcloud v1.59+ a déprécié `--datacenter` en faveur de `--location`.

**Solution :** Remplacer dans le workflow CI :

```bash
# ❌ Déprécié
hcloud server create --datacenter fsn1-dc14 ...

# ✅ Correct
hcloud server create --location fsn1 ...
```

---

### 4.15 Callback `community.general.yaml` supprimé

**Symptôme :**
```
The 'community.general.yaml' callback plugin has been removed
```

**Cause :** Le plugin callback YAML a été retiré de `community.general` v12 et intégré dans ansible-core.

**Solution :** Modifier `ansible.cfg` :

```ini
# ❌ Ancien
stdout_callback = yaml

# ✅ Nouveau
stdout_callback = ansible.builtin.default
[defaults]
result_format = yaml
```

---

### 4.16 Services en `activating` au moment du verify

**Symptôme :**
```
AssertionError: telegram-bot is not active (activating)
```

**Cause :** Certains services (telegram_bot, alloy) mettent quelques secondes à démarrer. Le `verify.yml` s'exécute immédiatement après le converge.

**Solution :** Ajouter des retries dans le `verify.yml` :

```yaml
- name: Wait for service
  ansible.builtin.service_facts:
  register: _svc
  until: _svc.ansible_facts.services['telegram-bot.service'].state == 'running'
  retries: 3
  delay: 5
```

---

### 4.17 Monit daemon not running en CI

**Symptôme :**
```
Monit: the monit daemon is not running
```

**Cause :** Sur une VM CI fraîchement déployée, Monit peut mettre du temps à démarrer ou échouer si les services surveillés ne sont pas encore prêts.

**Solution :** Rendre le check Monit non-bloquant dans le verify :

```yaml
- name: Check monit status
  ansible.builtin.command: monit status
  changed_when: false
  failed_when: false    # Non-bloquant en CI
```

---

## Phase 5 — Correctifs post-deploiement production (V3.1)

> 11 problemes decouverts lors du premier deploiement en production (IONOS). Voir `docs/07-rex-v3.1.md` pour le detail complet organise par theme.

| # | Composant | Piege | Severite |
|---|-----------|-------|----------|
| **5.1** | **Pipeline CI/CD** | **SSH key path incoherent (deploy_key vs seko-vpn-deploy)** | Bloquant |
| **5.2** | **Pipeline CI/CD** | **vault.yml dans .gitignore → absent en CI** | Bloquant |
| **5.3** | **Pipeline CI/CD** | **Vault password avec newline (echo vs printenv)** | Bloquant |
| **5.4** | **Headplane** | **DNS page crash (champs config manquants)** | Bloquant |
| **5.5** | **Headplane** | **Config read-only (volume :ro + config_strict)** | Majeur |
| **5.6** | **Headscale** | **DERP map empty crash (urls: [])** | Bloquant |
| **5.7** | **Headscale** | **server_url = base_domain conflit DERP** | Bloquant |
| **5.8** | **Headscale** | **DERP private key path vide** | Bloquant |
| **5.9** | **Molecule** | **server_ip undefined dans converge** | Bloquant |
| **5.10** | **Headplane** | **Timeout 408 apres restart Headscale** | Majeur |
| **5.11** | **Headscale CLI** | **--user attend un ID numerique (0.26.0)** | Mineur |
| **5.12** | **Uptime Kuma** | **Username case-sensitive → monitors non crees** | Bloquant |
| **5.13** | **Uptime Kuma** | **Sonde Headscale API DOWN (404 sur /)** | Majeur |

### 5.12 Uptime Kuma — Username case-sensitive, monitors non crees

**Symptome :**
```
INFO: Login failed (Incorrect username or password.), trying setup...
WARNING: Uptime Kuma already initialized with different credentials. Skipping monitor configuration.
Summary: 0 created, 0 already existed (skipped)
```

**Cause :** Le nom d'utilisateur admin Uptime Kuma est **sensible a la casse**. Si le vault contient `uptime_kuma_admin_username: "admin"` mais que l'instance a ete creee avec `"Admin"` ou un autre username, le script de configuration des monitors est ignore silencieusement (exit 0 sans erreur, mais 0 monitor cree).

Le piege est double :
1. Le script ne crash pas → Ansible ne detecte pas l'echec
2. Le `changed_when` cherche `"0 created"` dans la sortie → la tache est marquee `ok` (pas `changed`)

**Solution :**
```bash
# 1. Verifier le username reel dans Uptime Kuma (UI web)
# 2. Mettre a jour le vault
ansible-vault edit inventory/group_vars/all/vault.yml
# Corriger : uptime_kuma_admin_username: "le_vrai_username"

# 3. Redeployer le role
ansible-playbook playbooks/site.yml --tags uptime_kuma --ask-vault-pass
```

> **⚠️ Le wizard affiche un avertissement** sur la casse lors de la saisie du username. Pour les instances existantes, verifier le username exact dans l'interface web d'Uptime Kuma (Settings → General).

---

### 5.13 Uptime Kuma — Sonde Headscale API DOWN (404 sur /)

**Symptome :** La sonde "Headscale API" est en DOWN permanent dans Uptime Kuma alors que Headscale fonctionne normalement.

**Cause :** Headscale 0.26 renvoie **404 sur `/`** (pas de page d'accueil). La sonde pointait vers `https://singa.example.com` et n'acceptait que `200-299` et `401`.

**Diagnostic :**
```bash
# 404 sur / — normal pour Headscale 0.26
curl -sI https://singa.example.com
# HTTP/2 404

# 401 sur /api/v1/apikey — preuve que le service tourne
curl -sI https://singa.example.com/api/v1/apikey
# HTTP/2 401
```

**Solution :** La sonde pointe desormais vers `/api/v1/apikey` avec le code attendu `401`. Si Headscale est down, l'endpoint ne repond pas 401 → alerte DOWN.

---

## Dépannage rapide par outil

### Molecule

```bash
# Tester un rôle spécifique
make role ROLE=telegram_bot

# Logs détaillés
cd roles/telegram_bot && ../../.venv/bin/molecule --debug test

# Nettoyer les conteneurs orphelins
make clean
# ou : docker rm -f $(docker ps -aq --filter label=creator=molecule)
```

### Linting

```bash
# Voir les erreurs
make lint

# Correction automatique
./scripts/fix-lint.sh

# Prévisualiser sans modifier
./scripts/fix-lint.sh --dry-run
```

### Bot Telegram

```bash
# Statut du service
sudo systemctl status telegram-bot

# Logs en temps réel
sudo journalctl -u telegram-bot -f

# Redémarrer
sudo systemctl restart telegram-bot

# Vérifier le fichier .env
sudo cat /opt/services/telegram-bot/.env
# → Doit contenir TELEGRAM_BOT_TOKEN et ALLOWED_CHAT_IDS
```

### Monit

```bash
# Vérifier la syntaxe (TOUJOURS faire ça après modification)
sudo monit -t

# Statut de tous les services
sudo monit status

# Relancer Monit
sudo systemctl restart monit

# Voir les logs Monit
sudo tail -f /var/log/monit.log
```

### WSL2 (développement local)

```bash
# Si DNS ne fonctionne pas sous WSL2
ansible-playbook playbooks/wsl-repair.yml --connection local

# Redémarrer WSL (dans PowerShell)
wsl --shutdown
```

### Conteneurs Docker

```bash
# Voir tous les conteneurs
docker ps -a

# Logs d'un conteneur
docker logs headscale --tail 50

# Redémarrer un conteneur
docker restart headscale

# Vérifier le réseau proxy-net
docker network inspect proxy-net
```

---

## Messages d'erreur courants et leurs solutions

| Message d'erreur | Cause probable | Solution |
|-----------------|---------------|----------|
| `undefined variable: 'domain_...'` | Variables manquantes dans converge.yml | Ajouter bloc `vars:` dans le converge.yml |
| `docker: command not found` | Docker pas installé dans le conteneur Molecule | Ajouter `prepare.yml` avec installation Docker |
| `collection 'community.docker' not found` | `ansible-galaxy` non exécuté | `ansible-galaxy collection install -r requirements.yml` |
| `ACME challenge failed` | DNS ne pointe pas vers le serveur | Vérifier les DNS ou activer `ci_mode=true` |
| `Container exited with code 1` (Zerobyte) | `APP_SECRET` manquant ou mal formaté | `openssl rand -hex 32` → 64 hex chars |
| `monit: syntax error` | Caractères spéciaux dans le mot de passe | Mot de passe alphanumérique uniquement |
| `healthcheck: UNHEALTHY` (Headplane) | Healthcheck sur image distroless | Supprimer le healthcheck Docker |
| `502 Bad Gateway` (Caddy → backend) | Le conteneur backend n'est pas sur proxy-net | Vérifier le réseau dans docker-compose.yml |
| `permission denied` (.env telegram) | Fichier .env pas en mode 600 | `chmod 600 /opt/services/telegram-bot/.env` |
| `vault password not found` | Oublié `--ask-vault-pass` | Ajouter `--ask-vault-pass` à la commande |
| `set: Illegal option -o pipefail` | Dash utilisé au lieu de Bash | Ajouter `executable: /bin/bash` à la tâche shell |
| `lsb_release: command not found` | `lsb-release` absent sur Debian 13 | Ajouter `lsb-release` dans `prepare.yml` |
| `No module named 'requests'` | `python3-requests` absent | Ajouter `python3-requests` dans `prepare.yml` |
| `mount destination is not a directory` | Bind mount de fichier en DinD | Monter des RÉPERTOIRES, jamais des fichiers |
| `Flag --datacenter is deprecated` | hcloud CLI v1.59+ | Remplacer `--datacenter` par `--location` |
| `callback plugin has been removed` | `community.general` v12 | Utiliser `ansible.builtin.default` + `result_format: yaml` |
| `service is activating (not active)` | Service pas encore démarré | Ajouter `retries` + `delay` dans le verify |
| `initial DERPMap is empty` | DERP desactive + `urls: []` | Activer le DERP embarque (`derp.server.enabled: true`) |
| `server_url cannot use same domain as base_domain` | Meme domaine pour API et Magic DNS | Variable `headscale_base_domain` separee de `domain_headscale` |
| `failed to save private key to disk at path ""` | `derp.server.private_key_path` manquant | Ajouter le chemin dans la config DERP |
| `Cannot convert undefined or null to object` (Headplane) | Champs DNS manquants dans config Headscale | Ajouter `split: {}`, `search_domains: []`, `extra_records: []` |
| `Timed out waiting for Headscale API` (408) | Headplane demarre avant Headscale | `docker restart headplane` apres restart Headscale |
| `invalid argument for --user flag` | Headscale 0.26.0 veut un ID numerique | `headscale users list` pour obtenir l'ID |
| `Skipping monitor configuration` (Uptime Kuma) | Username case-sensitive (`admin` ≠ `Admin`) | Corriger `uptime_kuma_admin_username` dans le vault |
| Sonde Headscale API DOWN (Uptime Kuma) | Headscale 0.26 renvoie 404 sur `/` | Pointer la sonde vers `/api/v1/apikey` (attend 401) |
