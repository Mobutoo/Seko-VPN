#!/usr/bin/env bash
# ============================================================
# fix-lint.sh — Corrige les 27 violations ansible-lint
# Lancer depuis la racine du repo : bash fix-lint.sh
# ============================================================
set -euo pipefail

echo "═══════════════════════════════════════════"
echo "  Fix des 27 violations ansible-lint"
echo "═══════════════════════════════════════════"

# ──────────────────────────────────────────────
# Fix 1/4 : fqcn — locale_gen (roles/common)
# ──────────────────────────────────────────────
echo "[1/4] Fix fqcn: ansible.builtin.locale_gen → community.general.locale_gen"
sed -i 's/ansible\.builtin\.locale_gen/community.general.locale_gen/' \
  roles/common/tasks/main.yml
echo "  ✅ roles/common/tasks/main.yml"

# ──────────────────────────────────────────────
# Fix 2/4 : risky-shell-pipe + line-length
#           Tous les prepare.yml (7 rôles identiques)
# ──────────────────────────────────────────────
echo "[2/4] Fix risky-shell-pipe + line-length: prepare.yml (7 rôles)"

PREPARE_FILES=(
  roles/caddy/molecule/default/prepare.yml
  roles/headplane/molecule/default/prepare.yml
  roles/headscale/molecule/default/prepare.yml
  roles/portainer/molecule/default/prepare.yml
  roles/uptime_kuma/molecule/default/prepare.yml
  roles/vaultwarden/molecule/default/prepare.yml
  roles/zerobyte/molecule/default/prepare.yml
)

for f in "${PREPARE_FILES[@]}"; do
  if [[ -f "$f" ]]; then
    python3 -c "
with open('$f') as fh:
    content = fh.read()

# Fix 1: GPG key — ajouter pipefail
content = content.replace(
    '''    - name: Ajouter la clé GPG Docker
      ansible.builtin.shell:
        cmd: |
          install -m 0755 -d /etc/apt/keyrings
          curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg''',
    '''    - name: Ajouter la clé GPG Docker
      ansible.builtin.shell:
        cmd: |
          set -o pipefail
          install -m 0755 -d /etc/apt/keyrings
          curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg''')

# Fix 2: Dépôt Docker — ajouter pipefail + découper longue ligne
content = content.replace(
    '''    - name: Ajouter le dépôt Docker
      ansible.builtin.shell:
        cmd: |
          echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \$(lsb_release -cs) stable\" | tee /etc/apt/sources.list.d/docker.list''',
    '''    - name: Ajouter le dépôt Docker
      ansible.builtin.shell:
        cmd: |
          set -o pipefail
          echo \"deb [arch=\$(dpkg --print-architecture) \\\\
            signed-by=/etc/apt/keyrings/docker.gpg] \\\\
            https://download.docker.com/linux/debian \\\\
            \$(lsb_release -cs) stable\" \\\\
            | tee /etc/apt/sources.list.d/docker.list''')

with open('$f', 'w') as fh:
    fh.write(content)
"
    echo "  ✅ $f"
  fi
done

# ──────────────────────────────────────────────
# Fix 3/4 : risky-shell-pipe + line-length
#           roles/docker/tasks/main.yml
#           roles/alloy/tasks/main.yml
# ──────────────────────────────────────────────
echo "[3/4] Fix risky-shell-pipe: docker + alloy"

# --- docker/tasks/main.yml ---
python3 -c "
with open('roles/docker/tasks/main.yml') as f:
    content = f.read()

# Fix GPG key pipe
content = content.replace(
    '''- name: Ajouter la clé GPG Docker officielle
  ansible.builtin.shell:
    cmd: |
      install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
      chmod a+r /etc/apt/keyrings/docker.gpg
    creates: /etc/apt/keyrings/docker.gpg''',
    '''- name: Ajouter la clé GPG Docker officielle
  ansible.builtin.shell:
    cmd: |
      set -o pipefail
      install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
      chmod a+r /etc/apt/keyrings/docker.gpg
    creates: /etc/apt/keyrings/docker.gpg''')

# Fix dépôt Docker pipe + line-length
content = content.replace(
    '''- name: Ajouter le dépôt Docker
  ansible.builtin.shell:
    cmd: |
      echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \$(lsb_release -cs) stable\" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    creates: /etc/apt/sources.list.d/docker.list''',
    '''- name: Ajouter le dépôt Docker
  ansible.builtin.shell:
    cmd: |
      set -o pipefail
      echo \"deb [arch=\$(dpkg --print-architecture) \\\\
        signed-by=/etc/apt/keyrings/docker.gpg] \\\\
        https://download.docker.com/linux/debian \\\\
        \$(lsb_release -cs) stable\" \\\\
        | tee /etc/apt/sources.list.d/docker.list > /dev/null
    creates: /etc/apt/sources.list.d/docker.list''')

with open('roles/docker/tasks/main.yml', 'w') as f:
    f.write(content)
print('  ✅ roles/docker/tasks/main.yml')
"

# --- alloy/tasks/main.yml ---
python3 -c "
with open('roles/alloy/tasks/main.yml') as f:
    content = f.read()

content = content.replace(
    '''- name: Ajouter la clé GPG Grafana
  ansible.builtin.shell:
    cmd: curl -fsSL https://apt.grafana.com/gpg.key | gpg --dearmor --yes -o /usr/share/keyrings/grafana.gpg
    creates: /usr/share/keyrings/grafana.gpg''',
    '''- name: Ajouter la clé GPG Grafana
  ansible.builtin.shell:
    cmd: |
      set -o pipefail
      curl -fsSL https://apt.grafana.com/gpg.key | gpg --dearmor --yes -o /usr/share/keyrings/grafana.gpg
    creates: /usr/share/keyrings/grafana.gpg''')

with open('roles/alloy/tasks/main.yml', 'w') as f:
    f.write(content)
print('  ✅ roles/alloy/tasks/main.yml')
"

# ──────────────────────────────────────────────
# Fix 4/4 : no-changed-when — hardening swap
# ──────────────────────────────────────────────
echo "[4/4] Fix no-changed-when: hardening swap task"

python3 -c "
with open('roles/hardening/tasks/main.yml') as f:
    content = f.read()

# Le task précédent check 'swapon --show' dans hardening_swap_check
# Si stdout est vide → pas de swap → on crée
content = content.replace(
    '''- name: Créer le fichier swap
  ansible.builtin.command:
    cmd: \"{{ item }}\"
  loop:''',
    '''- name: Créer le fichier swap
  ansible.builtin.command:
    cmd: \"{{ item }}\"
  when: hardening_swap_check.stdout == \"\"
  loop:''')

with open('roles/hardening/tasks/main.yml', 'w') as f:
    f.write(content)
print('  ✅ roles/hardening/tasks/main.yml')
"

echo ""
echo "═══════════════════════════════════════════"
echo "  ✅ 27 violations corrigées"
echo "  Relancez : make lint"
echo "═══════════════════════════════════════════"
