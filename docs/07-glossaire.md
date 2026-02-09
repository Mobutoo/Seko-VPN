# 📖 Glossaire

> Définitions des termes techniques utilisés dans le projet Seko-VPN. Si tu es junior et que tu rencontres un terme que tu ne connais pas, cherche-le ici.

---

## A

**ACME (Automatic Certificate Management Environment)**
Protocole utilisé par Let's Encrypt pour délivrer automatiquement des certificats SSL. Caddy utilise ACME pour obtenir et renouveler les certificats sans intervention manuelle.

**Ansible**
Outil d'automatisation qui permet de configurer des serveurs à distance via SSH. On écrit des "playbooks" en YAML qui décrivent l'état voulu du serveur. Ansible se charge d'appliquer les changements nécessaires.

**ansible-lint**
Outil qui vérifie que le code Ansible respecte les bonnes pratiques. Le profil "production" est le plus strict (celui utilisé dans ce projet).

**ansible-vault**
Outil intégré à Ansible pour chiffrer des fichiers de secrets. Les fichiers chiffrés peuvent être commités dans Git en toute sécurité.

---

## B

**Bootstrap**
Première étape de préparation d'un serveur. Dans Seko-VPN, `bootstrap-vps.sh` crée l'utilisateur et configure SSH sur un VPS neuf.

**Bridge (réseau Docker)**
Type de réseau Docker qui permet aux conteneurs de communiquer entre eux par leur nom. `proxy-net` est le réseau bridge utilisé par tous les conteneurs Seko-VPN.

---

## C

**Caddy**
Serveur web / reverse proxy qui obtient automatiquement des certificats SSL via Let's Encrypt. Plus simple que Nginx pour ce cas d'usage.

**Caddyfile**
Fichier de configuration de Caddy. Dans Seko-VPN, c'est un template Jinja2 (`Caddyfile.j2`) qui est rendu avec les variables Ansible.

**CI/CD (Continuous Integration / Continuous Delivery)**
Pratique consistant à tester automatiquement chaque changement de code (CI) et à le déployer automatiquement (CD). Dans Seko-VPN, GitHub Actions exécute les 3 stages (lint, molecule, integration) à chaque push.

**ci_mode**
Variable Seko-VPN qui, quand elle vaut `true`, force Caddy à utiliser des certificats auto-signés au lieu de Let's Encrypt. Utilisée dans le pipeline CI pour tester sans DNS réels.

**Collection Ansible**
Ensemble de modules, rôles et plugins distribués ensemble. `community.docker` est la collection qui fournit le module `docker_compose_v2`.

**Compose (Docker Compose)**
Outil pour définir et gérer des applications Docker multi-conteneurs via un fichier `docker-compose.yml`. La V5 est la version actuelle (plugin CLI).

**Converge (Molecule)**
Étape de Molecule qui exécute le rôle Ansible dans le conteneur de test. C'est l'équivalent de "lancer le déploiement".

---

## D

**DinD (Docker-in-Docker)**
Technique pour exécuter Docker à l'intérieur d'un conteneur Docker. Utilisée dans les tests Molecule pour les rôles qui déploient des conteneurs.

**Distroless**
Image Docker minimale qui ne contient QUE l'application, sans shell ni outils système. L'image Headplane est distroless, ce qui empêche les healthchecks et le debugging classique.

**DNS (Domain Name System)**
Système qui traduit les noms de domaine (ex: `vault.example.com`) en adresses IP. Les 6 sous-domaines de Seko-VPN doivent pointer vers l'IP du VPS.

---

## F

**Fail2Ban**
Outil qui surveille les logs de connexion et bloque automatiquement les IP qui tentent trop de connexions échouées (brute force SSH par exemple).

**forward_auth**
Mécanisme Caddy qui délègue l'authentification à un service externe (comme Authelia). Prévu pour V4.

---

## G

**GitOps**
Pratique où le dépôt Git est la source unique de vérité pour l'infrastructure. Tout changement passe par Git, est testé automatiquement, et déployé de manière reproductible.

**gpg --dearmor**
Commande qui convertit une clé GPG du format ASCII (texte) au format binaire. Utilisée lors de l'ajout de dépôts tiers (Docker, Grafana). Le flag `--yes` est obligatoire pour éviter un prompt interactif.

**Grafana Alloy**
Collecteur de logs et métriques développé par Grafana Labs. Remplace l'ancien Promtail. Dans Seko-VPN, il collecte les logs Docker et journald, prêt à les envoyer vers Loki.

---

## H

**Handler (Ansible)**
Action qui s'exécute uniquement quand elle est "notifiée" par une tâche. Exemple : si le template `Caddyfile.j2` change, le handler "Restart Caddy" est déclenché.

**Hardening**
Processus de sécurisation d'un système en réduisant sa surface d'attaque. Dans Seko-VPN, le rôle `hardening` configure les logs, NTP, swap, mises à jour auto, etc.

**Headless**
Se dit d'un service qui fonctionne sans interface graphique/web. Monit V3 est headless : pas d'interface web, accessible uniquement en SSH.

**Headplane**
Interface web pour administrer Headscale (le serveur VPN). Son image Docker est distroless, ce qui cause des contraintes spécifiques.

**Headscale**
Serveur VPN open-source compatible WireGuard. C'est une alternative self-hosted à Tailscale.

**Hetzner**
Hébergeur cloud allemand. Dans Seko-VPN, le pipeline CI utilise l'API Hetzner pour créer des VM éphémères de test (CX22 = 2 vCPU, 4 Go RAM).

**HSTS (HTTP Strict Transport Security)**
Header de sécurité qui force les navigateurs à toujours utiliser HTTPS. Configuré automatiquement par Caddy.

---

## I

**IaC (Infrastructure as Code)**
Pratique de gérer l'infrastructure (serveurs, réseaux, etc.) via du code versionné, au lieu de configurations manuelles.

**Idempotence**
Propriété d'une opération qui produit le même résultat qu'on l'exécute 1 fois ou N fois. Un rôle Ansible idempotent ne change rien si le serveur est déjà dans l'état voulu.

---

## J

**Jinja2**
Langage de template utilisé par Ansible. Les fichiers `.j2` contiennent des variables (`{{ variable }}`) et des conditions (`{% if ... %}`) qui sont rendues au moment du déploiement.

**journald**
Service systemd qui gère les logs du système. Dans Seko-VPN, il est limité à 500 Mo et 30 jours de rétention.

---

## L

**Let's Encrypt**
Autorité de certification gratuite qui délivre des certificats SSL via le protocole ACME. Caddy les obtient et les renouvelle automatiquement.

**Loki**
Système de stockage et d'indexation de logs développé par Grafana Labs. Prévu pour V4, avec Alloy comme collecteur.

**logrotate**
Outil Linux qui "tourne" les fichiers de logs : archive les anciens, compresse, et supprime ceux qui dépassent la rétention configurée.

---

## M

**Makefile**
Fichier qui définit des raccourcis de commandes. `make lint` exécute yamllint + ansible-lint, `make molecule` teste tous les rôles.

**Molecule**
Outil de test pour les rôles Ansible. Il crée un conteneur Docker, y exécute le rôle, vérifie le résultat, puis nettoie.

**Monit**
Outil de supervision système léger. Surveille les processus, les ressources, et peut redémarrer automatiquement les services qui crashent.

---

## N

**NTP (Network Time Protocol)**
Protocole de synchronisation de l'horloge. `chrony` est l'implémentation NTP utilisée dans Seko-VPN.

---

## O

**OOM Killer (Out Of Memory Killer)**
Mécanisme du kernel Linux qui tue les processus quand la RAM est épuisée. Le swap configuré par le rôle `hardening` réduit le risque d'OOM.

---

## P

**Pipeline CI**
Séquence automatisée d'étapes (lint → molecule → integration) qui valide le code à chaque push. Si une étape échoue, le merge est bloqué.

**Playbook (Ansible)**
Fichier YAML qui décrit une séquence de tâches à exécuter sur un ou plusieurs serveurs. `site.yml` est le playbook principal de Seko-VPN.

**PR (Pull Request)**
Demande de fusion d'une branche dans une autre sur GitHub. Permet la review de code et déclenche le pipeline CI.

**proxy-net**
Réseau Docker bridge partagé par tous les conteneurs de Seko-VPN. Caddy utilise ce réseau pour router le trafic vers les backends.

---

## R

**Reverse proxy**
Serveur qui reçoit les requêtes des clients et les redistribue aux services backend. Caddy est le reverse proxy de Seko-VPN.

**Rôle (Ansible)**
Unité modulaire de code Ansible. Chaque rôle gère un composant spécifique (Docker, Caddy, Monit, etc.).

**Rollback**
Action de revenir à un état précédent. En GitOps, c'est un `git revert` + redéploiement.

---

## S

**SSH (Secure Shell)**
Protocole de connexion sécurisée à distance. Ansible utilise SSH pour communiquer avec le VPS.

**SSL/TLS**
Protocoles de chiffrement qui sécurisent les connexions HTTPS. Les certificats sont obtenus automatiquement par Caddy via Let's Encrypt.

**sysctl**
Interface pour configurer les paramètres du kernel Linux à la volée. `kernel.panic=10` fait redémarrer le serveur 10 secondes après un kernel panic.

**systemd**
Système d'initialisation et de gestion des services sous Linux. Les services natifs (Monit, Alloy, Telegram Bot) sont gérés par systemd.

---

## T

**Tag (Ansible)**
Étiquette attachée à un rôle ou une tâche. Permet de n'exécuter qu'une partie du playbook : `--tags caddy` ne déploie que le rôle Caddy.

**Template (Ansible/Jinja2)**
Fichier modèle (`.j2`) dont les variables sont remplacées par leurs valeurs au moment du déploiement. Exemple : `Caddyfile.j2` → `Caddyfile`.

---

## U

**UFW (Uncomplicated Firewall)**
Interface simplifiée pour configurer le firewall Linux (iptables). Utilisé par le rôle `security` pour ouvrir uniquement les ports nécessaires.

**unattended-upgrades**
Paquet Debian qui installe automatiquement les mises à jour de sécurité. Configuré en mode "security-only" (pas les mises à jour de fonctionnalités).

**Uptime Kuma**
Outil de monitoring HTTP/TCP/DNS avec une interface web moderne, des graphiques d'historique et des pourcentages SLA.

---

## V

**Vault (ansible-vault)**
Système de chiffrement de fichiers intégré à Ansible. Le fichier `vault.yml` contient les secrets chiffrés en AES-256.

**Vaultwarden**
Implémentation open-source et légère du serveur Bitwarden (gestionnaire de mots de passe). Compatible avec les clients Bitwarden officiels.

**Verify (Molecule)**
Étape de Molecule qui vérifie que le rôle a bien configuré le système correctement. Exécute des assertions (le service est actif, le fichier existe, etc.).

**vhost (Virtual Host)**
Site web hébergé sur le même serveur avec un nom de domaine différent. Caddy gère 6 vhosts dans Seko-VPN.

**VPN (Virtual Private Network)**
Réseau privé virtuel. Headscale crée un VPN WireGuard qui permet de connecter des machines comme si elles étaient sur le même réseau local.

**VPS (Virtual Private Server)**
Serveur virtuel loué chez un hébergeur cloud. Seko-VPN est conçu pour être déployé sur un VPS Debian.

---

## W

**WireGuard**
Protocole VPN moderne, rapide et léger. Headscale l'utilise comme base pour créer le réseau VPN.

**Wizard**
Script interactif (`wizard.sh`) qui guide l'utilisateur à travers la configuration du projet en posant des questions avec des valeurs par défaut intelligentes.

---

## Y

**YAML**
Format de données lisible par l'humain utilisé par Ansible, Docker Compose, et les fichiers de configuration du projet. L'indentation est critique (2 espaces, pas de tabulations).

**yamllint**
Outil qui vérifie la syntaxe et le style des fichiers YAML.
