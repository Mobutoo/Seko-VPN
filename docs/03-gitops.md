# 🔄 GitOps & CI/CD — Le cœur du projet

> **Ce document est central.** Seko-VPN est un projet GitOps : le dépôt Git est la **source unique de vérité**. Tout changement passe par Git, est testé automatiquement, et déployé de manière reproductible. Ce document explique pourquoi, comment, et quelles sont les règles à respecter.

---

## 1. Qu'est-ce que le GitOps ?

### Le principe fondamental

> **"Si ce n'est pas dans Git, ça n'existe pas."**

En GitOps, on ne modifie JAMAIS un serveur à la main. Toute modification passe par le cycle :

```
1. Modifier le code dans une branche
2. Pousser vers GitHub (git push)
3. Le pipeline CI valide automatiquement
4. Si les tests passent → merge dans main
5. Déployer depuis main vers la production
```

### Pourquoi c'est important ?

| Problème sans GitOps | Solution avec GitOps |
|---------------------|---------------------|
| "Qui a modifié ce fichier sur le serveur ?" | Chaque changement a un commit avec auteur + date |
| "Le serveur A marche mais pas le B" | Le même code déploie exactement le même résultat |
| "J'ai cassé la config, comment revenir en arrière ?" | `git revert` + redéploiement |
| "Comment je sais si mon changement va casser la prod ?" | Le pipeline CI teste AVANT le merge |
| "Le serveur a été configuré il y a 6 mois, personne ne sait comment" | Le code Ansible documente l'état exact du serveur |

### Les 4 piliers GitOps dans Seko-VPN

```
┌─────────────────────────────────────────────────────────────────┐
│                        GitOps — 4 piliers                        │
├─────────────────┬──────────────────┬──────────────┬─────────────┤
│ 1. Déclaratif   │ 2. Versionné     │ 3. Automatisé│ 4. Observable│
│                 │                  │              │             │
│ Ansible décrit  │ Git stocke tout  │ Pipeline CI  │ Monitoring  │
│ l'ÉTAT voulu du │ l'historique des │ valide auto- │ vérifie que │
│ serveur, pas les│ changements avec │ matiquement  │ l'état réel │
│ commandes pour  │ qui/quand/quoi   │ chaque push  │ = état voulu│
│ y arriver       │                  │              │             │
└─────────────────┴──────────────────┴──────────────┴─────────────┘
```

---

## 2. Stratégie de branches

### Le modèle Git de Seko-VPN

```
main ─────────●────────●────────●────────●──────── (production)
              ▲        ▲        ▲        ▲
              │        │        │        │
develop ──●──●──●──●──●──●──●──●──●──●──●──●──── (intégration)
          ▲     ▲     ▲     ▲
          │     │     │     │
feature/  │  fix/     │  feature/
hardening │  monit    │  telegram-bot
          │  acl      │
          │           │
       feature/    feature/
       uptime-kuma alloy
```

### Les branches

| Branche | Rôle | Qui y pousse | Protégée ? |
|---------|------|-------------|------------|
| `main` | Production — l'état EXACT du serveur de prod | Personne directement (merge uniquement) | **Oui** |
| `develop` | Intégration — les features en cours | Merge des branches feature/ | **Oui** |
| `feature/<nom>` | Développement d'une fonctionnalité | Le développeur | Non |
| `fix/<nom>` | Correction d'un bug | Le développeur | Non |
| `hotfix/<nom>` | Correction urgente en production | Le développeur → merge direct dans main | Non |

### Règles de protection des branches

**Pour `main` :**
- ❌ Pas de push direct
- ✅ Merge uniquement via Pull Request
- ✅ Pipeline CI doit passer (les 3 stages)
- ✅ Au moins 1 review (si travail en équipe)
- ✅ Le job `integration` (VM Hetzner) doit réussir

**Pour `develop` :**
- ❌ Pas de push direct
- ✅ Merge via Pull Request
- ✅ Pipeline CI doit passer (stages lint + molecule)

---

## 3. Workflow de contribution complet

### Scénario : "Je veux modifier le rôle Caddy"

```bash
# 1. Se mettre à jour depuis develop
git checkout develop
git pull origin develop

# 2. Créer une branche feature
git checkout -b feature/caddy-ajout-headers

# 3. Faire les modifications
vim roles/caddy/templates/Caddyfile.j2
# ... modifications ...

# 4. Tester localement (OBLIGATOIRE avant de pousser)
make lint                           # Vérifie la syntaxe YAML + règles Ansible
make role ROLE=caddy                # Teste le rôle avec Molecule

# 5. Commiter avec un message clair
git add roles/caddy/
git commit -m "feat(caddy): ajouter headers de sécurité HSTS"

# 6. Pousser la branche
git push origin feature/caddy-ajout-headers

# 7. Créer une Pull Request sur GitHub : feature/caddy-ajout-headers → develop
#    Le pipeline CI se déclenche automatiquement

# 8. Si le CI passe → merge dans develop
# 9. Quand develop est stable → PR develop → main
# 10. Après merge dans main → déployer en prod
```

### Convention de messages de commit

```
<type>(<scope>): <description>

Types:
  feat     → Nouvelle fonctionnalité
  fix      → Correction de bug
  docs     → Documentation uniquement
  refactor → Refactoring sans changement fonctionnel
  test     → Ajout/modification de tests
  ci       → Changement pipeline CI/CD
  chore    → Maintenance (versions, dépendances)

Exemples:
  feat(telegram-bot): ajouter commande /backup
  fix(monit): corriger le template monitrc pour Debian 13
  docs: ajouter la procédure de rollback
  ci: ajouter Trivy scanning dans le pipeline
  test(hardening): ajouter vérification swap dans verify.yml
```

---

## 4. Le pipeline CI/CD — 3 stages

### Vue d'ensemble

```
git push / Pull Request
      │
      ▼
  ┌─────────────┐     ┌──────────────────────────┐     ┌─────────────────────────┐
  │  STAGE 1    │     │  STAGE 2                 │     │  STAGE 3                │
  │  LINT       │────▶│  MOLECULE                │────▶│  INTEGRATION            │
  │             │     │                          │     │                         │
  │ yamllint    │     │ Matrice 14 rôles         │     │ VM Hetzner CX22         │
  │ ansible-lint│     │ en parallèle             │     │ éphémère                │
  │ (profil     │     │ Docker-in-Docker         │     │ ci_mode=true            │
  │  production)│     │                          │     │ (main seulement)        │
  │             │     │ ~5-10 min                │     │ ~10-15 min              │
  │ ~1-2 min    │     │                          │     │                         │
  └─────────────┘     └──────────────────────────┘     └─────────────────────────┘
        │                       │                               │
   Si échec →              Si échec →                     Si échec →
   ❌ PR bloquée          ❌ PR bloquée                  ❌ PR bloquée
```

### Stage 1 : Lint (toutes les branches)

**Objectif :** Vérifier la syntaxe et les bonnes pratiques AVANT de tester.

```yaml
# Ce qui est vérifié :
yamllint .                              # Syntaxe YAML valide
ansible-lint --profile production       # Règles Ansible strictes (0 erreur)
```

**Erreurs courantes attrapées par le lint :**
- Indentation YAML incorrecte
- Variables non préfixées par le nom du rôle
- Utilisation de `shell` au lieu d'un module Ansible
- Valeurs octales implicites (ex: `mode: 0644` au lieu de `mode: "0644"`)
- Handlers sans majuscule en première lettre

> **💡 Astuce :** Lance `make lint` localement AVANT de pousser pour gagner du temps. Tu peux aussi corriger automatiquement : `./scripts/fix-lint.sh`

### Stage 2 : Molecule (toutes les branches)

**Objectif :** Tester chaque rôle individuellement dans un conteneur Docker isolé.

```
Matrice parallèle : 14 rôles × 1 image Debian 12

Chaque rôle exécute :
  1. create    → Crée le conteneur de test
  2. prepare   → Installe les prérequis (Docker pour les 7 rôles conteneurs)
  3. converge  → Exécute le rôle Ansible
  4. verify    → Vérifie que tout est en place
  5. destroy   → Nettoie le conteneur
```

**Les 4 types de rôles Molecule :**

| Type | Rôles | Image | `prepare.yml` requis ? |
|------|-------|-------|----------------------|
| Base | common, security | `geerlingguy/docker-debian12-ansible` | Non |
| Docker (DinD) | docker | `geerlingguy/docker-debian12-ansible` | Non |
| Conteneur | caddy, headscale, headplane, vaultwarden, portainer, zerobyte, uptime_kuma | `geerlingguy/docker-debian12-ansible` | **Oui** (installe Docker + proxy-net) |
| Systemd | monit, hardening, alloy, telegram_bot | `trfore/docker-debian12-systemd` | Non |

> **⚠️ Piège critique :** Chaque `converge.yml` DOIT avoir un bloc `vars:` avec des valeurs mock. Molecule ne charge PAS le `inventory/group_vars/`. Sans ce bloc, les rôles échouent avec `undefined variable`.

### Stage 3 : Integration (branche `main` uniquement)

**Objectif :** Tester le déploiement COMPLET des 14 rôles sur une vraie VM.

```
1. Hetzner API → Crée une VM CX22 (2 vCPU, 4 Go RAM)
2. Connexion SSH en root
3. ansible-playbook site.yml --extra-vars "ci_mode=true" --extra-vars "@tests/ci-vars.yml"
4. Vérification que tout tourne
5. Destruction de la VM (if: always() → même si le test échoue)
```

**Le `ci_mode` expliqué :**

| Sans ci_mode | Avec ci_mode=true |
|-------------|-------------------|
| Caddy demande des certificats Let's Encrypt | Caddy utilise des certificats auto-signés (`local_certs`) |
| Les DNS doivent pointer vers le serveur | Domaines fictifs `*.ci-test.local` |
| ❌ Échoue sur une VM éphémère (DNS incorrects) | ✅ Fonctionne sans DNS réels |

**Ce qui est validé en CI vs. en production :**

| Aspect | CI | Prod |
|--------|:--:|:----:|
| Déploiement 14 rôles | ✅ | ✅ |
| Templates rendus | ✅ | ✅ |
| Conteneurs démarrés | ✅ | ✅ |
| Réseau proxy-net | ✅ | ✅ |
| Services systemd | ✅ | ✅ |
| Certificats SSL Let's Encrypt | ❌ | ✅ |
| DNS résolution réelle | ❌ | ✅ |

### Secrets GitHub Actions requis

| Secret | À configurer dans | Usage |
|--------|-------------------|-------|
| `HCLOUD_TOKEN` | GitHub → Settings → Secrets | Token API Hetzner pour créer les VM |
| `SSH_PRIVATE_KEY` | GitHub → Settings → Secrets | Clé SSH pour se connecter aux VM |
| `VAULT_PASSWORD` | GitHub → Settings → Secrets | Déchiffrer vault.yml pendant les tests |

> **⚠️ Comment configurer les secrets GitHub :** Va dans ton repo GitHub → `Settings` → `Secrets and variables` → `Actions` → `New repository secret`. Les secrets ne sont JAMAIS visibles une fois enregistrés.

---

## 5. Commandes Makefile (développement local)

Le `Makefile` fournit des raccourcis pour toutes les opérations courantes :

```bash
# ─── Lint ───────────────────────────────────────
make lint                  # yamllint + ansible-lint (profil production)

# ─── Molecule (tests) ──────────────────────────
make molecule              # Tester TOUS les 14 rôles
make role ROLE=hardening   # Tester un seul rôle
make role ROLE=caddy       # Tester un autre rôle

# ─── Utilitaires ───────────────────────────────
make wizard                # Lancer le wizard de configuration
make clean                 # Nettoyer les conteneurs Molecule orphelins
```

> **💡 Règle d'or :** Toujours lancer `make lint && make role ROLE=<ton-role>` AVANT de `git push`.

---

## 6. Workflow GitOps pour un déploiement en production

### Déploiement initial

```bash
# Depuis la branche main
git checkout main
git pull origin main

# Déployer
ansible-playbook playbooks/site.yml --ask-vault-pass
```

### Mise à jour d'un service

```bash
# 1. Créer une branche
git checkout -b feature/update-vaultwarden-version

# 2. Modifier la version dans vars.yml
#    vaultwarden_version: "1.36.0-alpine"

# 3. Tester
make role ROLE=vaultwarden

# 4. Commit + Push + PR → develop → main

# 5. Après merge dans main, déployer le rôle seul
git checkout main && git pull
ansible-playbook playbooks/site.yml --ask-vault-pass --tags vaultwarden
```

### Rollback (retour en arrière)

Si un déploiement casse quelque chose :

```bash
# 1. Identifier le commit qui a cassé les choses
git log --oneline -10

# 2. Revenir au commit précédent
git revert <commit-hash>
git push origin main

# 3. Redéployer
ansible-playbook playbooks/site.yml --ask-vault-pass
```

> **💡 C'est la force du GitOps :** chaque état du serveur correspond à un commit Git. Revenir en arrière = revenir au commit précédent + redéployer.

---

## 7. Infrastructure as Code (IaC) — Les règles

### Règle 1 : Ne JAMAIS modifier le serveur à la main

```
❌ ssh serveur → vim /etc/monit/monitrc → systemctl restart monit
✅ vim roles/monit/templates/monitrc.j2 → commit → push → CI → deploy
```

**Pourquoi ?** Si tu modifies le serveur à la main :
- Le prochain `ansible-playbook site.yml` écrasera tes changements
- Personne ne saura que tu as fait une modification
- Si le serveur crash, tes modifications sont perdues

### Règle 2 : Tout changement passe par une PR

Même un "petit fix" doit passer par le pipeline CI. Un changement anodin dans un template Jinja2 peut casser le linting, un test Molecule, ou le déploiement complet.

### Règle 3 : Les secrets restent dans vault.yml

```
❌ Hardcoder un mot de passe dans un template
❌ Commiter un fichier .env avec des tokens
✅ Stocker dans vault.yml → référencer avec {{ vault_xxx }}
```

### Règle 4 : L'idempotence est non-négociable

Chaque rôle Ansible doit pouvoir être relancé N fois sans effet de bord. Concrètement :

```bash
# Premier run : installe et configure tout
ansible-playbook site.yml    # changed=42

# Deuxième run : ne change rien (tout est déjà en place)
ansible-playbook site.yml    # changed=0
```

Si `changed > 0` au deuxième run, il y a un problème dans le rôle.

---

## 8. Gestion des secrets avec ansible-vault

### Qu'est-ce que ansible-vault ?

C'est un outil de chiffrement intégré à Ansible. Il chiffre tes fichiers de secrets avec AES-256 (le même algorithme que les banques).

### Commandes essentielles

```bash
# Créer un fichier vault chiffré
ansible-vault create inventory/group_vars/all/vault.yml

# Éditer un fichier vault (le déchiffre temporairement)
ansible-vault edit inventory/group_vars/all/vault.yml

# Voir le contenu sans modifier
ansible-vault view inventory/group_vars/all/vault.yml

# Changer le mot de passe vault
ansible-vault rekey inventory/group_vars/all/vault.yml

# Déployer (Ansible demande le mot de passe)
ansible-playbook playbooks/site.yml --ask-vault-pass
```

### Le fichier vault.yml dans Git

```yaml
# Ce que Git voit (fichier chiffré) :
$ANSIBLE_VAULT;1.1;AES256
36326139363430336461643534333739...

# Ce que ansible-vault edit montre (contenu déchiffré) :
vault_system_user_password: "abcdef123456"
vault_vaultwarden_admin_token: "token_secret"
# ...
```

> **🔒 Le fichier vault.yml chiffré est SAFE à commiter dans Git.** Il ne peut être lu que par quelqu'un qui connaît le mot de passe vault.

---

## 9. Le pipeline CI en détail

### Fichier `.github/workflows/ci.yml` — Structure

```yaml
name: CI Pipeline

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

jobs:
  # ─── Stage 1 : Lint ───
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Setup Python
      - name: Install dependencies
        run: |
          pip install ansible ansible-lint yamllint
          ansible-galaxy collection install -r requirements.yml
      - name: Lint
        run: |
          yamllint .
          ansible-lint --profile production

  # ─── Stage 2 : Molecule ───
  molecule:
    needs: lint                        # Attend que lint passe
    runs-on: ubuntu-latest
    strategy:
      matrix:
        role:                          # 14 rôles en parallèle
          - common
          - security
          - docker
          - hardening
          - caddy
          - headscale
          - headplane
          - vaultwarden
          - portainer
          - zerobyte
          - uptime_kuma
          - monit
          - alloy
          - telegram_bot
    steps:
      - uses: actions/checkout@v4
      - name: Setup Python + deps
      - name: Install collections
        run: ansible-galaxy collection install -r requirements.yml
      - name: Run Molecule
        run: |
          cd roles/${{ matrix.role }}
          molecule test

  # ─── Stage 3 : Integration ───
  integration:
    needs: molecule                    # Attend que molecule passe
    if: github.ref == 'refs/heads/main'  # Main seulement
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Setup Hetzner VM
        run: |
          # Crée une VM CX22 éphémère via l'API Hetzner
          hcloud server create --name ci-test --type cx22 --image debian-12
      - name: Deploy
        run: |
          ansible-galaxy collection install -r requirements.yml
          ansible-playbook playbooks/site.yml \
            --extra-vars "ci_mode=true" \
            --extra-vars "@tests/ci-vars.yml"
      - name: Cleanup (toujours exécuté)
        if: always()
        run: hcloud server delete ci-test
```

### Pourquoi `ansible-galaxy` dans les 3 jobs ?

Chaque job CI s'exécute dans un runner Ubuntu propre. Les collections Ansible (comme `community.docker`) ne sont PAS installées par défaut. Sans `ansible-galaxy collection install -r requirements.yml`, les rôles échouent avec :

```
ERROR! the role 'xxx' was not found in [...] the collection 'community.docker' was not found
```

> **💡 C'est le piège 2.13 documenté dans le REX.** C'est une erreur que beaucoup font.

---

## 10. Procédure de hotfix en production

Quand quelque chose est cassé en prod et qu'il faut corriger immédiatement :

```bash
# 1. Créer la branche hotfix depuis main
git checkout main
git pull origin main
git checkout -b hotfix/monit-crash-loop

# 2. Corriger le problème
vim roles/monit/templates/monitrc.j2

# 3. Tester localement
make role ROLE=monit

# 4. Commit + Push
git commit -am "fix(monit): corriger la boucle de restart sur Debian 13"
git push origin hotfix/monit-crash-loop

# 5. PR directement vers main (cas exceptionnel)
# → Le CI doit quand même passer

# 6. Après merge, déployer immédiatement
git checkout main && git pull
ansible-playbook playbooks/site.yml --ask-vault-pass --tags monit

# 7. Reporter le fix dans develop
git checkout develop
git merge main
git push origin develop
```

---

## 11. Checklist avant chaque merge

### Avant de merge dans `develop`

- [ ] `make lint` passe sans erreur
- [ ] `make role ROLE=<role-modifié>` passe
- [ ] Le pipeline CI (lint + molecule) est vert
- [ ] Le message de commit suit la convention
- [ ] Les fichiers modifiés sont cohérents (pas de debug oublié)

### Avant de merge dans `main`

- [ ] Tout ce qui est dans la checklist `develop`
- [ ] Le pipeline CI complet (lint + molecule + integration) est vert
- [ ] La PR a été reviewée (si travail en équipe)
- [ ] Les secrets vault.yml sont à jour si nécessaire
- [ ] La documentation est mise à jour si l'architecture change

### Avant de déployer en production

- [ ] `main` est à jour (`git pull`)
- [ ] Les DNS sont en place (si nouveaux domaines)
- [ ] Le mot de passe vault est prêt
- [ ] Un test post-déploiement est planifié (/status Telegram, URLs)

---

## 12. Bonnes pratiques GitOps récapitulées

| # | Règle | Pourquoi |
|---|-------|---------|
| 1 | **Un commit = un changement logique** | Facilite le rollback et la review |
| 2 | **Jamais de push force sur main/develop** | Préserve l'historique |
| 3 | **Toujours tester localement avant de push** | Réduit les allers-retours CI |
| 4 | **Les secrets dans vault.yml, jamais en clair** | Sécurité des accès |
| 5 | **Pas de modification manuelle sur le serveur** | Garantit la reproductibilité |
| 6 | **Le pipeline CI est le gardien** | Bloque les PR qui cassent quelque chose |
| 7 | **Documenter les choix dans les commits** | "Pourquoi" est plus important que "quoi" |
| 8 | **Utiliser les tags Ansible pour les déploiements partiels** | Évite de tout redéployer |
| 9 | **Monitorer après chaque déploiement** | `/status` + Uptime Kuma |
| 10 | **Garder develop proche de main** | Évite les divergences et conflits |
