# 🔔 Uptime Kuma — Monitors (état réel + gap API-level)

**Contexte :** T0.5 du plan `~/work/ops/loops/PLAN.md` (2026-07-17), suite à l'incident Plane
du jour (frontend 200 pendant que l'API répondait 500 — non détecté par Kuma).

**Statut de cette tâche : PARTIAL.** Les monitors « infra » (ce dépôt) sont vérifiés live.
Les monitors « API-level » applicatifs (Plane, LiteLLM, Qdrant, n8n) sont **spécifiés mais
non déployés** — un blocker structurel (Caddy VPN-enforce) les rendrait aveugles, cf. §3.

---

## 1. État live constaté (2026-07-17T00:34Z, lecture seule via l'API Kuma)

Énuméré directement sur l'instance en cours d'exécution (`docker exec`-équivalent, credentials
déjà rendues sur la box par `roles/uptime_kuma`, jamais affichées).

| id | Monitor | Type | Actif | Intervalle | Source IaC |
|----|---------|------|-------|------------|------------|
| 2 | Headplane UI | HTTP | oui | 60s | `roles/uptime_kuma` |
| 3 | Vaultwarden | HTTP | oui | 60s | `roles/uptime_kuma` |
| 4 | Portainer | HTTP | oui | 60s | `roles/uptime_kuma` |
| 5 | Zerobyte | HTTP | oui | 120s | `roles/uptime_kuma` |
| 6 | Uptime Kuma | HTTP | oui | 120s | `roles/uptime_kuma` |
| 7 | SSH | Port | oui | 120s | `roles/uptime_kuma` |
| 8 | DNS singa.ewutelo.cloud | DNS | oui | 300s | `roles/uptime_kuma` |
| 9 | Headscale API | HTTP | oui | 60s | `roles/uptime_kuma` |
| 10 | Javisi Backups | Push | oui | 60s | **hors IaC** (créé manuellement dans l'UI, absent de `configure-monitors.py.j2` — drift à noter, non corrigé ici, hors périmètre T0.5) |

**9 monitors au total**, une seule notification configurée : **Seko Telegram**
(id=1, type telegram, `isDefault=True`) — c'est le canal utilisé par tous les monitors
ci-dessus et par le test d'alerte §4.

**Correction du postulat de la tâche** : le rôle `VPAI/roles/uptime-config` (souvent
raccourci « uptime-config » dans les briefs) ne crée **aucun** monitor live — il génère
uniquement un fichier Markdown de référence (`/opt/javisi/docs/uptime-kuma-monitors.md` sur
Sese-AI) destiné à une création **manuelle** dans l'UI Kuma. Les 6 monitors applicatifs qu'il
documente (HTTPS, n8n, Grafana, PostgreSQL, TLS, Backup Heartbeat) **n'existent pas** dans la
liste ci-dessus : soit ils n'ont jamais été créés manuellement, soit ils ont été supprimés.
Seuls les 8 monitors infra Seko-VPN + 1 push manuel sont live aujourd'hui.

---

## 2. Ce qui a été ajouté par cette tâche

Rien n'a été déployé en live sur les monitors API-level (voir §3 — blocker). Le travail livré :

- `VPAI/roles/uptime-config/defaults/main.yml` : nouvelle liste
  `uptime_kuma_monitors_api_level_blocked` — 3 définitions prêtes (Plane API en 401-as-up,
  LiteLLM `/v1/models`, Qdrant health) + note explicite que n8n est déjà couvert par le
  monitor existant `{{ project_display_name }} — n8n` (`/healthz`) une fois le blocker levé.
- `VPAI/roles/uptime-config/templates/uptime-kuma-monitors.md.j2` : nouvelle section
  « Bloqué — monitors API-level » qui rend cette liste séparément des monitors « prêts à
  créer », pour ne pas laisser croire qu'ils sont opérationnels.
- Ce document (état live + blocker + preuve du test d'alerte).

---

## 3. Blocker : Kuma (Seko-VPN) ne peut pas voir l'état applicatif réel

**Constat vérifié par `curl` depuis la box Seko-VPN elle-même** (2026-07-17) :

```
work.ewutelo.cloud/api/v1/users/me/  -> 403
work.ewutelo.cloud/                  -> 403
llm.ewutelo.cloud/v1/models          -> 403
qd.ewutelo.cloud/healthz             -> 403
qd.ewutelo.cloud/readyz              -> 403
mayi.ewutelo.cloud/healthz           -> 403
```

**Cause racine** : `VPAI/roles/caddy/templates/Caddyfile.j2` gate ces vhosts derrière
`import vpn_only`, qui n'autorise que `client_ip` dans `caddy_vpn_cidr` (100.64.0.0/10,
Tailscale) ou `caddy_docker_frontend_cidr` (172.20.1.0/24, Docker bridge côté Sese). Seko-VPN
est le **serveur de contrôle Headscale**, pas un client du mesh : `tailscale` n'est pas
installé sur la box (`command -v tailscale` échoue) et il n'existe **aucune route** vers
`100.64.0.0/10` (`ip route` ne montre rien). Toute requête HTTP publique depuis Seko-VPN vers
ces domaines est donc bloquée par Caddy **avant** d'atteindre le backend — Kuma ne verra
jamais un 401/500/404 applicatif, seulement le 403 de Caddy, qui est constant que le backend
soit sain ou en panne (c'est exactement l'incident qu'on essaie de détecter).

Seul `LiteLLM` a un mécanisme de contournement (`caddy_trusted_app_ips`), et il n'inclut pas
l'IP de Seko-VPN aujourd'hui. Plane, Qdrant, n8n n'ont **aucun** mécanisme de contournement
dans le Caddyfile actuel.

**Conséquence** : configurer ces monitors avec `accepted_statuscodes: ["401"]` (ou tout autre
code applicatif) les rendrait "UP" en permanence via le 403 Caddy — un faux signal actif,
pire que l'absence de monitor. **Non déployé, volontairement.**

**Deux options de correction (gate humaine — aucune appliquée par cette tâche)** :

1. **Enrôler Seko-VPN comme client du tailnet** via le rôle `VPAI/roles/headscale-node`
   déjà existant (même pattern prévu pour le NAS PX58, T1.1 du plan loops). Lui donnerait une
   IP `100.64.x.x` qui satisferait `caddy_vpn_cidr` nativement, sans toucher au Caddyfile.
   C'est le chemin **anticipé par le design actuel** — le commentaire "Scenario 3" du
   Caddyfile décrit déjà Seko-VPN relayant du trafic via le mesh.
2. **Étendre le mécanisme `caddy_trusted_app_ips`** (aujourd'hui LiteLLM seulement) aux vhosts
   Plane/Qdrant/n8n, et y ajouter l'IP publique de Seko-VPN (87.106.30.160). Change la surface
   de sécurité de 3 services supplémentaires — à valider explicitement (audit §4.2 style).

Option 1 est recommandée (cohérente avec le design existant, zéro changement de la posture
Caddy). Nécessite un `ansible-playbook --tags headscale-node` ciblé sur `vps` (Seko-VPN) côté
VPAI, une clé de pré-auth Headscale, et une revue humaine avant application.

---

## 4. Verify (b) — preuve de la chaîne d'alerte (indépendante du blocker §3)

Le pipeline d'alerte Kuma → Telegram fonctionne, testé de bout en bout le 2026-07-17T00:32Z :

1. Monitor temporaire créé : `loops-test-alert`, type HTTP, cible
   `https://loops-test-alert.invalid/` (TLD réservé RFC 2606, NXDOMAIN garanti), intervalle
   20s, `maxretries: 0`, notification `Seko Telegram` (id=1) attachée.
2. Premier heartbeat en échec, marqué **important** par Kuma (déclenche la notification) :
   ```
   STATUS MonitorStatus.DOWN
   IMPORTANT_HEARTBEAT status=DOWN msg='getaddrinfo ENOTFOUND loops-test-alert.invalid'
   ```
3. Log applicatif Kuma corrobore (token/chat-id absents de ce log — rien à scrubber) :
   ```
   [MONITOR] WARN: Monitor #11 'loops-test-alert': Failing: getaddrinfo ENOTFOUND loops-test-alert.invalid | Interval: 20 seconds | Type: http | Down Count: 0 | Resend Interval: 0
   ```
4. Monitor supprimé immédiatement après : `DELETED monitor id=11`, confirmation
   `REMAINING_WITH_NAME 0`, `TOTAL_MONITORS_NOW 9` (retour à l'état initial).

Limite honnête : cette preuve démontre que Kuma a marqué l'événement "important" et l'a
associé à la notification Telegram déjà active pour les 9 monitors en production (donc au
même pipeline qui alerte réellement l'opérateur aujourd'hui) — elle ne constitue pas une
capture d'écran du message Telegram reçu (pas d'accès au téléphone/chat depuis cet agent).

---

## 5. Prochaine étape

1. Décision humaine sur l'option 1 ou 2 du §3 (gate superviseur du plan loops).
2. Une fois le blocker levé : déployer `uptime_kuma_monitors_api_level_blocked`
   (VPAI/roles/uptime-config) → renommer en `uptime_kuma_monitors` (fusion), regénérer la doc
   via `ansible-playbook --tags uptime-config`, créer les monitors dans l'UI Kuma en suivant
   le Markdown généré, réattacher `Seko Telegram`.
3. Régler le drift noté §1 (`Javisi Backups` absent de l'IaC) — hors périmètre ici.
