#!/usr/bin/env bash
# ============================================================
# fix-molecule-final.sh — Fix DÉFINITIF de tous les échecs CI
#
# 4 causes racines identifiées dans les logs CI :
#
# CAUSE 1 (8 rôles) : "set -o pipefail" → /bin/sh est dash, pas bash
#   Fix : ajouter executable: /bin/bash à toutes les tasks shell avec pipefail
#
# CAUSE 2 (1 rôle) : "invalid characters in sha512_crypt salt"
#   Fix : salt alphanumérique pur (pas d'underscore)
#
# CAUSE 3 (2 rôles) : "No package matching 'curl'/'ufw'"
#   Fix : update_cache: true + prepare.yml
#
# CAUSE 4 (3 rôles) : "System has not been booted with systemd"
#   Fix : command: /sbin/init dans molecule.yml
#
# Usage : cd Seko-VPN && bash fix-molecule-final.sh
# ============================================================
set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[FIX]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}  $*"; }
count=0

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Fix DÉFINITIF — 14 rôles molecule CI"
echo "═══════════════════════════════════════════════════"
echo ""

# ──────────────────────────────────────────────
# CAUSE 1 : pipefail + dash
# Ajouter "executable: /bin/bash" à toutes les tasks
# ansible.builtin.shell qui contiennent "set -o pipefail"
# ──────────────────────────────────────────────
info "CAUSE 1/4 : pipefail — ajout executable: /bin/bash"

python3 << 'PYFIX1'
import glob, os

def fix_pipefail_executable(filepath):
    """Ajoute executable: /bin/bash aux tasks shell avec pipefail"""
    with open(filepath) as f:
        content = f.read()

    if 'set -o pipefail' not in content:
        return False

    if 'executable: /bin/bash' in content:
        print(f'  ⏭️  {filepath} (déjà corrigé)')
        return False

    # Pattern : après "ansible.builtin.shell:" et "cmd: |" qui contient pipefail
    # On doit ajouter "executable: /bin/bash" au même niveau que "cmd:"
    lines = content.split('\n')
    new_lines = []
    i = 0
    modified = False

    while i < len(lines):
        line = lines[i]
        new_lines.append(line)

        # Détecter "ansible.builtin.shell:"
        if 'ansible.builtin.shell:' in line:
            shell_indent = len(line) - len(line.lstrip())
            # Chercher cmd: dans les lignes suivantes
            j = i + 1
            found_cmd = False
            cmd_indent = 0
            while j < len(lines) and j < i + 5:
                if 'cmd:' in lines[j]:
                    found_cmd = True
                    cmd_indent = len(lines[j]) - len(lines[j].lstrip())
                    break
                j += 1

            if found_cmd:
                # Vérifier si pipefail est dans le bloc cmd
                has_pipefail = False
                k = j
                while k < len(lines) and k < j + 10:
                    if 'set -o pipefail' in lines[k]:
                        has_pipefail = True
                        break
                    # Si on arrive à un autre attribut au même niveau que cmd:, on arrête
                    if k > j and lines[k].strip() and not lines[k].strip().startswith('#'):
                        line_indent = len(lines[k]) - len(lines[k].lstrip())
                        if line_indent <= cmd_indent and not lines[k].strip().startswith('-') and not lines[k].strip().startswith('set ') and not lines[k].strip().startswith('curl') and not lines[k].strip().startswith('echo') and not lines[k].strip().startswith('install') and not lines[k].strip().startswith('chmod'):
                            break
                    k += 1

                if has_pipefail:
                    # Chercher si "creates:" ou "when:" ou "register:" existe après le bloc cmd
                    # pour insérer executable: au bon endroit
                    # On insère juste après la ligne ansible.builtin.shell:
                    # Trouver la fin du bloc shell (creates, when, register, ou prochain task)
                    end_of_shell = j
                    m = j + 1
                    while m < len(lines):
                        stripped = lines[m].strip()
                        if stripped == '':
                            end_of_shell = m - 1
                            break
                        line_indent = len(lines[m]) - len(lines[m].lstrip())
                        if line_indent <= shell_indent and stripped.startswith('- '):
                            end_of_shell = m - 1
                            break
                        if stripped.startswith('creates:') or stripped.startswith('when:') or stripped.startswith('register:') or stripped.startswith('changed_when:'):
                            end_of_shell = m
                        m += 1
                    else:
                        end_of_shell = len(lines) - 1

                    # Insérer "executable: /bin/bash" au même niveau que "cmd:"
                    # On le met juste AVANT cmd:
                    # Non, mieux : on le met comme attribut de shell au même niveau
                    pass  # On va gérer ça différemment
                    modified = True

        i += 1

    # Approche plus simple et fiable : sed-like replacement
    # Ajouter "executable: /bin/bash" après chaque "cmd: |" qui est suivi de pipefail
    content_new = content
    
    # Pattern pour les blocs shell avec cmd: | suivi de pipefail
    import re
    
    # Trouver tous les blocs "ansible.builtin.shell:\n    cmd: |"
    # et ajouter executable après le bloc
    
    # Approche la plus simple : après "creates:" qui suit un pipefail, ou après le dernier
    # attribut du bloc shell
    
    # En fait, la façon la plus propre est d'ajouter à la ligne shell elle-même
    # Non, c'est un attribut séparé.
    
    # Utilisons une approche ligne par ligne plus simple
    lines = content.split('\n')
    result = []
    i = 0
    modified = False
    
    while i < len(lines):
        result.append(lines[i])
        
        # Si on trouve "ansible.builtin.shell:" → vérifier si le bloc a pipefail
        if 'ansible.builtin.shell:' in lines[i] and 'executable' not in content[content.index(lines[i]):content.index(lines[i])+500]:
            shell_line = lines[i]
            shell_indent = len(shell_line) - len(shell_line.lstrip())
            
            # Regarder les 15 prochaines lignes pour pipefail
            lookahead = '\n'.join(lines[i:i+15])
            if 'set -o pipefail' in lookahead:
                # Trouver où insérer executable: (juste après cmd: | ... creates:)
                # Le plus simple : on cherche "creates:" dans les lignes suivantes
                found_creates = False
                for j in range(i+1, min(i+15, len(lines))):
                    if lines[j].strip().startswith('creates:'):
                        # Insérer après creates
                        # On continue à ajouter les lignes normalement,
                        # et on marque pour insertion
                        pass
                
                # Encore plus simple : insérer "executable: /bin/bash" juste après "cmd:"
                # au même niveau d'indentation
                for j in range(i+1, min(i+5, len(lines))):
                    if 'cmd:' in lines[j]:
                        cmd_indent = len(lines[j]) - len(lines[j].lstrip())
                        # On n'insère pas ici car ça casserait le YAML
                        # On va plutôt modifier le shell: pour ajouter executable comme sibling
                        break
        
        i += 1

    # OK, approche ULTRA simple et qui marche :
    # Remplacer "ansible.builtin.shell:" par "ansible.builtin.shell:" puis
    # ajouter "executable: /bin/bash" comme argument supplémentaire
    
    lines = content.split('\n')
    result = []
    i = 0
    
    while i < len(lines):
        line = lines[i]
        result.append(line)
        
        if 'ansible.builtin.shell:' in line:
            indent = len(line) - len(line.lstrip())
            # Check if pipefail is in the next ~15 lines
            block = '\n'.join(lines[i:i+15])
            if 'set -o pipefail' in block and 'executable:' not in block:
                # Add executable right after the shell: line
                result.append(' ' * (indent + 2) + 'executable: /bin/bash')
                modified = True
        
        i += 1
    
    if modified:
        with open(filepath, 'w') as f:
            f.write('\n'.join(result))
        print(f'  ✅ {filepath}')
        return True
    
    return False

# Fix tous les fichiers avec pipefail
count = 0
for f in glob.glob('roles/*/tasks/main.yml'):
    if fix_pipefail_executable(f):
        count += 1

for f in glob.glob('roles/*/molecule/default/prepare.yml'):
    if fix_pipefail_executable(f):
        count += 1

print(f'  Total: {count} fichier(s) corrigé(s)')
PYFIX1

# ──────────────────────────────────────────────
# CAUSE 2 : salt invalide (underscore)
# sha512_crypt salt ne supporte que [a-zA-Z0-9./]
# ──────────────────────────────────────────────
info "CAUSE 2/4 : salt — caractères alphanumériques uniquement"

sed -i "s/password_hash('sha512', 'seko_salt_fixed')/password_hash('sha512', 'sekoSaltV3abcd')/" roles/common/tasks/main.yml
success "roles/common/tasks/main.yml (salt corrigé)"

# ──────────────────────────────────────────────
# CAUSE 3 : apt cache pas à jour
# Les images Docker n'ont pas un apt cache frais
# ──────────────────────────────────────────────
info "CAUSE 3/4 : apt cache — update_cache + prepare.yml"

# docker/tasks/main.yml — ajouter update_cache
python3 -c "
with open('roles/docker/tasks/main.yml') as f:
    content = f.read()
if 'update_cache: true' not in content:
    content = content.replace(
        '    state: present\n- name: Ajouter la clé',
        '    state: present\n    update_cache: true\n- name: Ajouter la clé'
    )
    with open('roles/docker/tasks/main.yml', 'w') as f:
        f.write(content)
    print('  ✅ roles/docker/tasks/main.yml')
else:
    print('  ⏭️  roles/docker/tasks/main.yml')
"

# security/tasks/main.yml — ajouter update_cache
python3 -c "
with open('roles/security/tasks/main.yml') as f:
    content = f.read()
if 'update_cache: true' not in content:
    content = content.replace(
        '    state: present\n- name:',
        '    state: present\n    update_cache: true\n- name:',
        1
    )
    with open('roles/security/tasks/main.yml', 'w') as f:
        f.write(content)
    print('  ✅ roles/security/tasks/main.yml')
else:
    print('  ⏭️  roles/security/tasks/main.yml')
"

# Créer prepare.yml pour rôles qui n'en ont pas
for role in security hardening common; do
  prep="roles/${role}/molecule/default/prepare.yml"
  if [[ ! -f "$prep" ]]; then
    mkdir -p "$(dirname "$prep")"
    cat > "$prep" << PREPEOF
---
- name: Prepare - Prerequisites for ${role}
  hosts: all
  become: true
  tasks:
    - name: Mettre à jour le cache apt
      ansible.builtin.apt:
        update_cache: true
PREPEOF
    success "$prep créé"
  fi
done

# common prepare.yml — ajouter passlib
COMMON_PREP="roles/common/molecule/default/prepare.yml"
if ! grep -q "passlib" "$COMMON_PREP" 2>/dev/null; then
  cat > "$COMMON_PREP" << 'PREPEOF'
---
- name: Prepare - Prerequisites for common
  hosts: all
  become: true
  tasks:
    - name: Mettre à jour le cache apt
      ansible.builtin.apt:
        update_cache: true
    - name: Installer pip
      ansible.builtin.apt:
        name: python3-pip
        state: present
    - name: Installer passlib (requis pour password_hash)
      ansible.builtin.pip:
        name: passlib
        state: present
      environment:
        PIP_BREAK_SYSTEM_PACKAGES: "1"
PREPEOF
  success "$COMMON_PREP (avec passlib)"
fi

# alloy prepare.yml — ajouter curl
ALLOY_PREP="roles/alloy/molecule/default/prepare.yml"
if [[ ! -f "$ALLOY_PREP" ]] || ! grep -q "curl" "$ALLOY_PREP" 2>/dev/null; then
  mkdir -p "$(dirname "$ALLOY_PREP")"
  cat > "$ALLOY_PREP" << 'PREPEOF'
---
- name: Prepare - Prerequisites for alloy
  hosts: all
  become: true
  tasks:
    - name: Mettre à jour le cache apt
      ansible.builtin.apt:
        update_cache: true
    - name: Installer curl et gnupg
      ansible.builtin.apt:
        name:
          - curl
          - gnupg
          - apt-transport-https
        state: present
PREPEOF
  success "$ALLOY_PREP (avec curl)"
fi

# telegram_bot prepare.yml
TGBOT_PREP="roles/telegram_bot/molecule/default/prepare.yml"
if [[ ! -f "$TGBOT_PREP" ]]; then
  mkdir -p "$(dirname "$TGBOT_PREP")"
  cat > "$TGBOT_PREP" << 'PREPEOF'
---
- name: Prepare - Prerequisites for telegram_bot
  hosts: all
  become: true
  tasks:
    - name: Mettre à jour le cache apt
      ansible.builtin.apt:
        update_cache: true
PREPEOF
  success "$TGBOT_PREP créé"
fi

# ──────────────────────────────────────────────
# CAUSE 4 : systemd pas PID 1
# Les images trfore/docker-debian12-systemd ont systemd
# mais molecule override le CMD
# ──────────────────────────────────────────────
info "CAUSE 4/4 : systemd — command: /sbin/init dans molecule.yml"

SYSTEMD_ROLES=(hardening telegram_bot monit alloy)

for role in "${SYSTEMD_ROLES[@]}"; do
  f="roles/${role}/molecule/default/molecule.yml"
  if [[ -f "$f" ]]; then
    python3 -c "
with open('$f') as fh:
    content = fh.read()

if 'trfore/docker-debian12-systemd' in content and 'command:' not in content:
    content = content.replace(
        'privileged: true',
        'privileged: true\n    command: /sbin/init\n    tmpfs:\n      - /run\n      - /tmp'
    )
    with open('$f', 'w') as fh:
        fh.write(content)
    print('  ✅ $f')
elif 'command:' in content:
    print('  ⏭️  $f (déjà configuré)')
else:
    print('  ⏭️  $f (pas systemd)')
"
  fi
done

# ──────────────────────────────────────────────
# Vérification finale
# ──────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════"
echo "  Vérification"
echo "═══════════════════════════════════════════════════"

echo ""
echo "pipefail sans executable: /bin/bash :"
for f in roles/*/tasks/main.yml roles/*/molecule/default/prepare.yml; do
  if [[ -f "$f" ]] && grep -q "set -o pipefail" "$f" && ! grep -q "executable: /bin/bash" "$f"; then
    echo "  ⚠️  $f"
  fi
done

echo ""
echo "shell tasks avec pipefail ET executable :"
for f in roles/*/tasks/main.yml roles/*/molecule/default/prepare.yml; do
  if [[ -f "$f" ]] && grep -q "set -o pipefail" "$f" && grep -q "executable: /bin/bash" "$f"; then
    echo "  ✅ $f"
  fi
done

echo ""
echo "Salt password_hash :"
grep "password_hash" roles/common/tasks/main.yml || echo "  ⚠️  pas trouvé"

echo ""
echo "molecule.yml systemd avec command: /sbin/init :"
for role in hardening telegram_bot monit alloy; do
  f="roles/${role}/molecule/default/molecule.yml"
  if [[ -f "$f" ]] && grep -q "command:" "$f"; then
    echo "  ✅ $f"
  else
    echo "  ⚠️  $f"
  fi
done

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Prochaines étapes :"
echo "  1. make lint"
echo "  2. Tester : cd roles/alloy && molecule destroy && molecule converge"
echo "  3. Tester : cd roles/common && molecule destroy && molecule converge"
echo "  4. git add -A && git commit && git push"
echo "═══════════════════════════════════════════════════"
