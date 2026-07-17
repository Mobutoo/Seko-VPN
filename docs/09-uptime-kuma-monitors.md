# 🔔 Uptime Kuma — Monitors (état réel + gap API-level)

**Contexte :** T0.5 du plan `~/work/ops/loops/PLAN.md` (2026-07-17), suite à l'incident Plane
du jour (frontend 200 pendant que l'API répondait 500 — non détecté par Kuma).

**Statut de cette tâche : DONE (2026-07-17T~11:15Z).** Le blocker §3 est résolu — Seko-VPN
est désormais enrôlé comme client du tailnet (Option 1, décision superviseur). Les 4
monitors API-level demandés (Plane, LiteLLM, Qdrant, n8n) sont **créés et live**, statut UP
confirmé pour les 4. Détail de la résolution en §6.
>
> **Correction (revue) :** une première passe n'avait créé que 3 des 4 monitors — n8n avait
> été (à tort) considéré comme "déjà couvert" par la définition documentaire de
> `uptime-config` (qui ne crée jamais rien en live, cf. §2). Le monitor `Javisi — n8n` a été
> créé explicitement en live pour combler ce trou (id=15, voir §1/§6).

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
| 12 | Javisi — Plane API (401-as-up) | HTTP | oui | 60s | `VPAI/roles/uptime-config` — créé 2026-07-17, **hors IaC de ce dépôt** (script ponctuel, cf §6) |
| 13 | Javisi — LiteLLM /v1/models | HTTP | oui | 60s | idem |
| 14 | Javisi — Qdrant health | HTTP | oui | 60s | idem |
| 15 | Javisi — n8n | HTTP | oui | 60s | idem |

**13 monitors au total**, une seule notification configurée : **Seko Telegram**
(id=1, type telegram, `isDefault=True`) — c'est le canal utilisé par tous les monitors
ci-dessus (y compris les 4 nouveaux, attachés explicitement par nom, `notificationIDList`
relu et confirmé `[1]` sur chacun) et par le test d'alerte §4.

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

## 3. Blocker : Kuma (Seko-VPN) ne peut pas voir l'état applicatif réel — RÉSOLU 2026-07-17

> **Résolu** via l'Option 1 ci-dessous (décision superviseur actée). Section conservée
> telle quelle comme trace du diagnostic d'origine ; voir §6 pour la résolution.


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

## 5. Prochaine étape — FAIT (2026-07-17)

1. ~~Décision humaine sur l'option 1 ou 2 du §3~~ — **Option 1 actée par le superviseur.**
2. ~~Une fois le blocker levé : déployer...~~ — **fait, voir §6.**
3. Régler le drift noté §1 (`Javisi Backups` absent de l'IaC) — **toujours hors périmètre**,
   non traité par cette tâche.
4. **Reste (hors périmètre T0.5, observé en vérifiant les statuts)** : le monitor `SSH` (id=7)
   est DOWN — `connect ECONNREFUSED 87.106.30.160:804`. `roles/uptime_kuma/defaults/main.yml`
   a `ssh_custom_port: 804`, mais le SSH public de Seko-VPN écoute sur le port **22**
   (confirmé `ssh seko` → port 22 dans `~/.ssh/config`, 804 est le port SSH de Sese-AI). Drift
   pré-existant, pas introduit par cette tâche — signalé, non corrigé ici.

## 6. Résolution — Seko-VPN enrôlé comme client du tailnet (2026-07-17)

**Option 1 appliquée** : `VPAI/roles/headscale-node` appliqué à Seko-VPN via le nouveau
playbook `VPAI/playbooks/utils/vpn-node-enroll.yml` (hosts: `vpn` — groupe déjà présent
dans `VPAI/inventory/hosts.yml`, aucun changement d'inventaire nécessaire). User Headscale
réutilisé : `mobuone` (id=2, déjà utilisé par les nœuds infra/service type
`memory-bulk-pod-*`) — pas de user superflu créé.

**Résultat** : Seko-VPN a désormais l'IP tailnet `100.64.0.5` (visible dans
`tailscale status` depuis waza). Les extra_records Headscale déjà vivants dans
`/opt/services/headscale/config/config.yaml` (`work/llm/mayi/qd.ewutelo.cloud` →
`100.64.0.14`) résolvent maintenant correctement **depuis la box elle-même** et
**depuis l'intérieur du conteneur `uptime-kuma`** (vérifié `docker exec uptime-kuma
getent hosts` + curl — même résolveur, aucun `extra_hosts` nécessaire) :

```
work.ewutelo.cloud/api/v1/users/me/  ->  401  (était 403)
llm.ewutelo.cloud/v1/models          ->  401  (était 403)
qd.ewutelo.cloud/healthz             ->  200  (était 403)
mayi.ewutelo.cloud/healthz           ->  200  (était 403)
```

Zéro changement de la posture Caddy — confirmé conforme au design anticipé (commentaire
"Scenario 3" du Caddyfile). Headscale et le SSH public de Seko-VPN sont restés intacts
pendant et après l'opération (vérifié : `sudo systemctl is-active headscale` conteneur Up,
`tailscale status` waza intact, `ssh seko` fonctionnel).

Les 4 monitors API-level demandés (Plane 401-as-up, LiteLLM /v1/models, Qdrant health, n8n)
ont été créés en live dans Kuma par un script ponctuel `uptime_kuma_api` (même méthode que
le test d'alerte §4, credentials lus depuis le fichier déjà rendu par Ansible sur la box —
jamais saisis ni affichés), notification `Seko Telegram` (id=1) attachée par nom et relue
après coup (`notificationIDList: [1]` confirmé sur les 4 via `get_monitor()`). Idempotent —
le script a été rejoué deux fois : d'abord `3 created` (Plane/LiteLLM/Qdrant, n8n oublié par
erreur), puis un rejeu avec n8n ajouté a donné `1 created, 3 already existed` (aucun doublon).
Statuts confirmés UP pour les 4 (401/401/200/200 respectivement). Ce script n'est **pas**
intégré à `roles/uptime_kuma/templates/configure-monitors.py.j2` (IaC de ce dépôt) — hors
périmètre de cette tâche (limité à la doc ici) ; à faire dans une tâche ultérieure pour éviter
le même type de drift que `Javisi Backups` (§1).

Défs sources : `VPAI/roles/uptime-config/defaults/main.yml` (fusionnées dans
`uptime_kuma_monitors`, l'ancien `uptime_kuma_monitors_api_level_blocked` n'existe plus).
Doc régénérée sur Sese-AI : `/opt/javisi/docs/uptime-kuma-monitors.md` (rôle `uptime-config`,
déployé `ansible-playbook playbooks/stacks/site.yml -e target_env=prod --tags uptime-config`).
