# 📚 Documentation Seko-VPN V3

> Infrastructure Ansible complète : VPN (Headscale), mots de passe (Vaultwarden), Docker UI (Portainer), sauvegardes (Zerobyte), monitoring (Uptime Kuma + Monit), collecteur de logs (Alloy), bot Telegram — le tout derrière Caddy avec SSL automatique.

**Version :** 3.0.0 · Février 2026
**Public cible :** Techniciens juniors & contributeurs
**Langue :** Français
**Statut CI/CD :** ✅ Pipeline validé (lint + 14 rôles Molecule + intégration Hetzner)

---

## Sommaire de la documentation

| # | Document | Description | Public |
|---|----------|-------------|--------|
| 1 | [Architecture](01-architecture.md) | Architecture système, réseau, services, flux de données | Tous |
| 2 | [Guide de déploiement](02-guide-deploiement.md) | Procédure pas-à-pas du premier déploiement à la production | Juniors |
| 3 | [GitOps & CI/CD](03-gitops.md) | Stratégie de branches, pipeline, workflows GitOps, bonnes pratiques | Tous |
| 4 | [Référence des rôles](04-roles-reference.md) | Les 14 rôles Ansible détaillés : variables, templates, dépendances | Contributeurs |
| 5 | [Dépannage & Erreurs](05-troubleshooting.md) | Les 42 pièges documentés (Day 0 → CI/CD Round 5) | Juniors |
| 6 | [Feuille de route V4](06-v4-roadmap.md) | Axes d'amélioration, priorisation, architecture cible V4 | Tous |
| 7 | [Glossaire](07-glossaire.md) | Définitions des termes techniques utilisés dans le projet | Juniors |
| 9 | [Uptime Kuma — Monitors](09-uptime-kuma-monitors.md) | État live des monitors, gap API-level et blocker VPN (T0.5 loops) | Contributeurs |

---

## Comment lire cette documentation ?

**Si tu es nouveau sur le projet :**

1. Commence par le [Glossaire](07-glossaire.md) pour comprendre les termes
2. Lis l'[Architecture](01-architecture.md) pour avoir une vue d'ensemble
3. Suis le [Guide de déploiement](02-guide-deploiement.md) étape par étape
4. Garde le [Dépannage](05-troubleshooting.md) sous la main en cas d'erreur

**Si tu veux contribuer au code :**

1. Lis [GitOps & CI/CD](03-gitops.md) pour comprendre le workflow de contribution
2. Consulte la [Référence des rôles](04-roles-reference.md) pour le rôle que tu modifies
3. Lance les tests localement avant de pusher (voir section Makefile)

**Si tu planifies la V4 :**

1. Lis la [Feuille de route V4](06-v4-roadmap.md) pour les axes prioritaires

---

## Chiffres clés du projet

```
14 rôles Ansible · 8 conteneurs Docker · 3 services natifs · 4 scripts
6 vhosts Caddy · 14 scénarios Molecule · Pipeline CI/CD 3 stages (validé)
~140 fichiers · 42 pièges documentés · ~40h de développement
```

---

## Liens rapides

| Ressource | Emplacement |
|-----------|-------------|
| README principal | [`../README.md`](../README.md) |
| Playbook principal | [`../playbooks/site.yml`](../playbooks/site.yml) |
| Wizard | [`../scripts/wizard.sh`](../scripts/wizard.sh) |
| Pipeline CI | [`../.github/workflows/ci.yml`](../.github/workflows/ci.yml) |
| Variables | [`../inventory/group_vars/all/vars.yml`](../inventory/group_vars/all/vars.yml) |
| Secrets (chiffrés) | [`../inventory/group_vars/all/vault.yml`](../inventory/group_vars/all/vault.yml) |
