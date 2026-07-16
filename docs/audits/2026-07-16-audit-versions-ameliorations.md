# Audit Seko-VPN — versions + améliorations (2026-07-16)

> Contexte : audit déclenché en marge du fix « bug création org Vaultwarden » (web-vault 2025.12.1 → `.find()` sur `passwordManagerPlans` undefined, upstream #6638, corrigé 1.35.2+). Seko-VPN est **sain** (SSH ok port 22, 33 j uptime ; la panne SSH était un faux négatif fail2ban, cf `VPAI/.planning/seeds/2026-07-16-seko-vpn-reinstall-handoff.md` §CADUC). Recherche versions via GitHub/Docker Hub API (subagent).

## 1. Montée de versions — tableau

| Composant | Actuel | Latest | Saut | Breaking / caveat |
|---|---|---|---|---|
| **Portainer** | `lts` (flottant) | **2.39.5** | pin | digest **identique** à `lts` → épinglage neutre. |
| **Uptime Kuma** | `latest` (flottant) | **2.4.0** | pin | fix RCE LiquidJS (admin-only). |
| **Vaultwarden** | 1.35.1 | **1.36.0** (ou 1.35.8) | minor | rien de breaking sur 8 releases ; 1.36.0 = fixes sécu (SSO CSRF, user/org enum, SSRF favicon). **1.35.8 déjà staged** (fix org, minimal). |
| **Caddy** | 2.9.1 | **2.11.4** | minor×2 | ⚠️ 2.10.0 casse libdns 1.0 → **rebuild xcaddy** du module `dns.providers.ovh` + retest ; 2.11.2 = 2 CVE (`forward_auth`, `vars_regexp`). |
| **Zerobyte** (backup) | v0.26.0 | **v0.41.0** | minor×15 | ⚠️ **v0.32.0 BREAKING** : suppression refs `env://`/`file://` ; v0.36.0 : allowlist webhooks. Régression backup = découverte au restore. |
| **Headplane** | 0.6.1 | **v0.7.0** | minor | verrouillé à Headscale (matrice) ; 0.7.0 refond OIDC. |
| **Headscale** | 0.26.0 | **v0.29.2** | minor×3 (8 hops) | 🔴 le plus risqué — voir §2. |

## 2. Headscale = risque maximal (plan de contrôle du mesh)

Upgrade **séquentiel non-skippable** (guide officiel) : 0.26.0→0.26.1→**0.27.0**→0.27.1→**0.28.0**→0.29.0→**0.29.2** (ne pas s'arrêter en 0.29.0 = régressif).
- **0.27.0** : migration SQLite majeure (réécriture schéma + FK enforcement) → **backup DB obligatoire avant**.
- **0.28.0** : « tags as identity » → tag/user-ownership mutuellement exclusifs → **revalider les ACL** après.
- **Client Tailscale min. relevé 3×** (1.64→1.74→1.80) → vérifier la version tailscale de **chaque nœud** (waza, sese, iphone, banga) AVANT l'upgrade serveur, sinon nœuds éjectés.
- **Headplane suit** : 0.6.1 sort de la matrice dès Headscale >0.27 → monter Headplane ≥0.6.2 (idéalement 0.7.0) **en même temps**.
- Risque local : `config.yaml` Headscale **non versionné** (noté `VPAI/.planning/codebase/CONCERNS.md`) → dérive possible pendant l'upgrade.

## 3. Améliorations (hors versions)

| # | Constat | Sévérité | Action |
|---|---|---|---|
| **A1** | **Backup non fonctionnel** : zerobyte (Restic) déployé mais son compose ne monte **aucun** volume applicatif (`headscale`/`vaultwarden`/`portainer`) → ne peut rien sauvegarder ; config runtime in-app, **hors IaC** (dérive, non reproductible). | 🔴 Critique | Monter les volumes cibles en `:ro` dans le compose zerobyte OU câbler dépôts Restic déclaratifs ; **prouver un restore** (cf plan coffre T1/T2, à fusionner ici). |
| **A2** | **Alloy inerte** : `alloy_loki_url: ""` → logs non expédiés. | 🟠 Majeur | Câbler vers Loki de sese (`tala`) ou retirer le rôle. |
| **A3** | **Tags flottants** : `portainer: lts`, `uptime_kuma: latest`. | 🟠 Majeur | Épingler 2.39.5 / 2.4.0 (§1, neutre). |
| **A4** | **DRY versions** : headscale/vaultwarden/portainer/zerobyte/headplane dupliqués `vars.yml` **et** role defaults → le default est inerte (a mordu : bump vaultwarden 1er essai sans effet). | 🟡 Moyen | `vars.yml` = source unique ; retirer les `*_version` des role defaults (ou les aligner). |
| **A5** | **Doc périmée** : troubleshooting §2.8 « 1.35.2 not found » (a induit le maintien en 1.35.1 = bug org) ; archi §01 dit `borgbase/vorta` alors que le rôle est `nicotsx/zerobyte`. | 🟡 Moyen | Corriger §2.8 + §01. |
| **A6** | **Seko hors tailnet** : `server_tailscale_ip: "87.106.30.160"` = IP **publique**. Admin SSH via net public → surface fail2ban. | 🟠 Majeur | **Objectif user** : joindre Seko au mesh Tailscale/Headscale + admin via 100.64.x. |
| **A7** | **SSH ban récurrent** : `ansible.cfg` sans `IdentitiesOnly` → essais multi-clés = échecs auth = ban. | ✅ **Corrigé** | `7daa7b0` (+ multiplexing `~/.ssh/config`). |
| **A8** | **SSH sur 22** (drift) : bascule 804 vit dans `playbooks/harden-ssh.yml` (jamais joué). ⚠️ le playbook pose `AllowUsers {{ system_user }}`(mobuone) mais `ansible.cfg remote_user=srvadmin` → **risque lock-out**. | 🟠 Majeur | **Objectif user** : jouer harden-ssh après avoir aligné l'user connecté ∈ AllowUsers. |

**Positifs** : auto-updates sécu (unattended-upgrades) ✓ ; molecule sur les 14 rôles ✓ ; `harden-ssh.yml` avec rollback auto ✓ ; 42 pièges documentés ✓.

## 4. Plan d'exécution proposé (par lots de risque)

**Lot 0 — débloquer** (attendre expiration ban ≤1 h, puis) : deploy `--tags vaultwarden` → applique **1.35.8** (fix org) + valider création org en navigation privée.

**Lot 1 — sûr, immédiat** (une fois SSH stable) : épingler `portainer 2.39.5` + `uptime_kuma 2.4.0` (§A3) ; corriger docs §A5 ; DRY versions §A4. Deploy `--tags portainer,uptime_kuma`. Risque ~nul.

**Lot 2 — backup d'abord** (A1, 🔴) : rendre zerobyte fonctionnel (montages volumes + restore prouvé) **AVANT** tout upgrade risqué. Fusionner avec le plan coffre T1/T2.

**Lot 3 — modéré, gated** : Caddy 2.11.4 (rebuild xcaddy module OVH + retest TLS) ; Vaultwarden →1.36.0 (snapshot avant) ; Alloy→Loki (A2).

**Lot 4 — session dédiée (mesh), gated 🔒** : Seko→Tailscale (A6) + bascule 804 (A8) + upgrade Headscale séquentiel 8-hop (A6 §2 : backup DB, check clients tailscale, ACL revalidées) + Headplane couplé. **Zerobyte** upgrade (breaking v0.32.0) dans ce lot ou le Lot 2 selon la migration `env://`.

## 5. Fait cette session
- `67c56fa`/`7daa7b0` : vaultwarden 1.35.8 (au bon niveau vars.yml), `IdentitiesOnly` anti-ban, multiplexing SSH.
- Reste bloqué sur : ban à expirer, puis Lot 0.
