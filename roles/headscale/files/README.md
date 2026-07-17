# Headscale ACL policy — DRAFT (`policy.hujson.draft`)

**Status: PREP ONLY.** This directory holds a draft replacement for the live
allow-all ACL (`roles/headscale/templates/policy.json.j2`). Nothing here is
wired into any Ansible task. Applying it requires the manual steps below —
**do not** copy it over the live template and redeploy without reading this
first. A bad Headscale ACL reload can strand every node (including the one
you're SSHed in from) outside the mesh.

## Why this exists

Audit finding (`docs/06-v4-roadmap.md` axe #5): the live policy is
`{"acls":[{"action":"accept","src":["*"],"dst":["*:*"]}]}` — allow-all. The
NAS PX58 runner (`ops/loops/PLAN.md` Phase 1, T1.1) is about to join the
tailnet into this flat network. This draft gives it (and every other node) an
explicit, commented, least-privilege set of rules instead.

## What changes, functionally

- Today: any node can reach any node on any port.
- After: only the flows below are allowed; everything else is denied.
  - waza (workstation) → everywhere (SSH + Caddy 443) — operator device.
  - seko (hub) → waza:8188/3200/3456 — existing live Caddy reverse-proxy to
    ComfyUI/Remotion/OpenCode (**breaks these 3 vhosts if this rule is
    dropped or mistyped** — see `roles/caddy/templates/Caddyfile.j2`).
  - sese (prod) → NAS:11434 — LiteLLM routing to the NAS-hosted Ollama model.
  - NAS → sese:443,3100 — LiteLLM calls + Alloy→Loki telemetry.
  - NAS → seko:443 only — Zerobyte backup retrieval for restore drills. No
    SSH, no Headplane/Portainer reach beyond what Caddy/443 exposes.
  - iPhone/banga (personal) → seko:443 only — Vaultwarden/Headplane UI.
  - DERP/STUN (udp/3478) stays open to `*` — standard practice, not a
    security boundary.

Full rationale and every assumption/caveat is commented inline in
`policy.hujson.draft` — read it before adjusting anything.

## Known gaps / things to verify before applying

1. **sese internal ports are assumed, not confirmed from this repo.** The
   `tag:prod:443` rules assume every sese-side service (n8n, LiteLLM,
   Grafana, Qdrant, Plane) is reachable cross-node only via Caddy/443, the
   same pattern as seko. Confirm against VPAI's `roles/caddy` + Docker
   network definitions before enabling.
2. **seko SSH port drift.** `inventory/group_vars/all/vars.yml` still says
   `ssh_custom_port: 804`, but the real sshd on seko listens on 22 (verified
   twice — see the caveat block at the top of the draft file). The draft
   uses 22. Re-check with `ssh -G seko | grep '^port'` before applying.
2b. **NAS SSH port** is assumed to be the default 22 (not bootstrapped yet
   at the time of writing) — confirm once `ops/loops/PLAN.md` T1.1 lands.
3. **Caddy is hostname-routed, not port-routed.** A rule that grants
   `tag:X:443` on seko grants reach to *every* Caddy vhost on seko
   (Headplane, Vaultwarden, Portainer, Zerobyte alike) — this ACL cannot
   express "NAS may reach Zerobyte's vhost but not Portainer's" at the
   network layer. If that separation becomes a real requirement, it needs
   either per-service host-published ports (breaking the current
   container-internal-only pattern) or a reverse-proxy-level control
   (Caddy `client_ip` + a second header/cert check). Out of scope here.
4. This draft does not touch UFW / Docker's own port exposure — it only
   changes what the **tailnet mesh** allows. A port that's host-published
   and reachable from the public internet (like Caddy 80/443 already is)
   stays reachable from the public internet regardless of this ACL.

## How to apply it — safely, incrementally

Headscale reloads its policy on every node's ACL evaluation (SIGHUP or
service restart), so a mistake here can affect the whole mesh at once.
Follow this order, do not skip steps:

1. **Backup the current state first.**
   ```bash
   ssh seko 'sudo cp /opt/services/headscale/config/policy.json \
     /opt/services/headscale/config/policy.json.bak-$(date +%Y%m%d)'
   ssh seko 'sudo cp -r /opt/services/headscale/config \
     /opt/services/headscale/config.bak-$(date +%Y%m%d)'
   ```
2. **Convert the draft to plain JSON** (Headscale 0.26.0 accepts HuJSON, but
   strip the trailing commas/comments if you want a byte-for-byte diffable
   file, or just point `policy.path` at the `.hujson` file directly — both
   work; HuJSON is a superset of JSON5-style comments).
3. **Dry-run the syntax only**, without touching the live container:
   ```bash
   ssh seko 'docker run --rm -v /opt/services/headscale/config:/etc/headscale:ro \
     headscale/headscale:0.26.0 headscale policy check --policy /etc/headscale/policy.json'
   ```
   (Adjust the sub-command to whatever `headscale policy` offers in 0.26.0 —
   verify with `headscale policy --help` inside the running container first;
   do this check BEFORE step 4, never skip it.)
4. **Apply to a copy, not the live file, and test from ONE node first.**
   Keep the live `policy.json` on allow-all. Load the draft into a second,
   throwaway Headscale instance (or a Molecule scenario) if at all possible.
   If testing directly against production is unavoidable:
   - Deploy the new policy.
   - `docker exec headscale headscale nodes list` to confirm all nodes are
     still registered (a bad policy does not deregister nodes, just blocks
     traffic).
   - From **waza only** (keep a second, already-open SSH session to seko as
     a safety net — see rollback below), test each flow in the "what
     changes" list above (`curl` the Caddy vhosts, `ssh` to each node).
   - Only widen to other nodes once waza's checks pass.
5. **Roll out to real config** via the Ansible role once verified: copy the
   validated JSON over `roles/headscale/templates/policy.json.j2` (adding
   back Jinja2 variables for IPs/tags if you want them templated instead of
   hardcoded), then `ansible-playbook ... --tags headscale` — this re-runs
   the "Deployer la policy ACL Headscale" task and the `Restart headscale`
   handler.
6. **Immediately re-verify** every flow in the "what changes" list from a
   node OTHER than the one you deployed from, in case the deploying node's
   own session masked a break.

## Rollback

If anything breaks (a node can no longer reach something it needs, or —
worst case — you lose SSH to a node):

```bash
# From the Ionos KVM console if SSH itself is broken
# (docs/runbooks/RUNBOOK-SEKO-VPN-RECOVERY-CONSOLE-IONOS.md in VPAI is the
# fallback entry point if seko itself becomes unreachable over SSH)
sudo cp /opt/services/headscale/config/policy.json.bak-<date> \
  /opt/services/headscale/config/policy.json
docker exec headscale kill -HUP 1   # or: docker compose restart headscale
docker exec headscale headscale nodes list   # confirm mesh intact
```

Headscale ACL changes do not require re-registering nodes — a bad policy is
always reversible by restoring the previous `policy.json` and reloading, as
long as you kept the backup from step 1.

## Never do this

- Never reload Headscale's policy without a backup of the previous file.
- Never test a tightened ACL from the ONLY node you have shell access to,
  without a second, already-authenticated session open as a safety net.
- Never widen this to "apply everywhere at once" before the single-node test
  in step 4 passes.
