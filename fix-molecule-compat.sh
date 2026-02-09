#!/usr/bin/env bash
# ============================================================
# fix-molecule-compat.sh — Fix global compatibilité Molecule/Docker
#
# Corrige TOUS les problèmes d'exécution en conteneur Docker :
#   1. passlib manquant (password_hash)
#   2. locale_gen (pas de /etc/locale.gen)
#   3. hostname (pas de systemd-hostnamed)
#   4. ufw (pas d'iptables/netfilter)
#   5. swapon/fallocate (pas de swap en conteneur)
#   6. sysctl (pas d'accès kernel)
#   7. service (systemd absent ou limité)
#
# Usage : cd Seko-VPN && bash fix-molecule-compat.sh
# ============================================================
set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[FIX]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}  $*"; }

DOCKER_WHEN='  when: ansible_virtualization_type != "docker"'

# ──────────────────────────────────────────────
# Fix 1 : passlib dans requirements-dev.txt
# ──────────────────────────────────────────────
info "Fix 1/7 : Ajouter passlib à requirements-dev.txt"
if ! grep -q "passlib" requirements-dev.txt; then
  echo "passlib>=1.7.0" >> requirements-dev.txt
  success "passlib ajouté"
else
  success "passlib déjà présent"
fi

# ──────────────────────────────────────────────
# Fix 2-7 : Ajouter when: docker aux tasks incompatibles
# Approche : Python pour un remplacement fiable
# ──────────────────────────────────────────────

python3 << 'PYFIX'
import re, os, glob

def add_docker_when(filepath, task_patterns):
    """
    Pour chaque task matchant un pattern, ajoute:
      when: ansible_virtualization_type != "docker"
    Si un when: existe déjà, ajoute la condition en liste.
    """
    with open(filepath) as f:
        content = f.read()

    original = content
    lines = content.split('\n')
    new_lines = []
    i = 0

    while i < len(lines):
        line = lines[i]
        stripped = line.rstrip()

        # Détecter un task name qui matche nos patterns
        matched = False
        for pattern in task_patterns:
            if pattern in stripped:
                matched = True
                break

        if matched:
            # Trouver l'indentation du task
            task_indent = len(line) - len(line.lstrip())

            # Collecter toutes les lignes du task
            task_lines = [line]
            j = i + 1
            while j < len(lines):
                next_line = lines[j]
                # Ligne vide ou commentaire → continuer
                if next_line.strip() == '' or next_line.strip().startswith('#'):
                    task_lines.append(next_line)
                    j += 1
                    continue
                # Nouvelle tâche au même niveau ou moins indenté → stop
                next_indent = len(next_line) - len(next_line.lstrip())
                if next_indent <= task_indent and next_line.strip().startswith('- '):
                    break
                task_lines.append(next_line)
                j += 1

            # Vérifier si when: ansible_virtualization_type est déjà présent
            has_docker_when = any('ansible_virtualization_type' in l for l in task_lines)

            if not has_docker_when:
                # Chercher un when: existant dans le task
                when_idx = None
                for k, tl in enumerate(task_lines):
                    if tl.strip().startswith('when:'):
                        when_idx = k
                        break

                if when_idx is not None:
                    # Un when: existe déjà — convertir en liste si nécessaire
                    when_line = task_lines[when_idx]
                    when_indent = len(when_line) - len(when_line.lstrip())

                    if '- ' in when_line.split('when:')[1] if 'when:' in when_line else False:
                        # Déjà une liste inline, ajouter après
                        pass
                    else:
                        when_value = when_line.split('when:')[1].strip()
                        if when_value and not when_value.startswith('\n'):
                            # when: single_condition → convertir en liste
                            # Vérifier si c'est déjà un format liste (lignes suivantes avec -)
                            is_list = False
                            for k2 in range(when_idx + 1, len(task_lines)):
                                tl2 = task_lines[k2].strip()
                                if tl2.startswith('- ') and len(task_lines[k2]) - len(task_lines[k2].lstrip()) > when_indent:
                                    is_list = True
                                    break
                                elif tl2 and not tl2.startswith('#'):
                                    break

                            if is_list:
                                # Ajouter notre condition à la liste existante
                                # Trouver la dernière ligne de la liste when
                                last_when_item = when_idx
                                for k2 in range(when_idx + 1, len(task_lines)):
                                    tl2 = task_lines[k2].strip()
                                    if tl2.startswith('- ') and len(task_lines[k2]) - len(task_lines[k2].lstrip()) > when_indent:
                                        last_when_item = k2
                                    elif tl2 and not tl2.startswith('#'):
                                        break
                                item_indent = ' ' * (when_indent + 4)
                                task_lines.insert(last_when_item + 1,
                                    f'{item_indent}- ansible_virtualization_type != "docker"')
                            else:
                                # when: single_value → when: list
                                task_lines[when_idx] = ' ' * when_indent + 'when:'
                                task_lines.insert(when_idx + 1,
                                    ' ' * (when_indent + 4) + f'- {when_value}')
                                task_lines.insert(when_idx + 2,
                                    ' ' * (when_indent + 4) + '- ansible_virtualization_type != "docker"')
                else:
                    # Pas de when: → ajouter à la fin du task (avant la dernière ligne vide)
                    insert_idx = len(task_lines)
                    # Retirer les lignes vides de fin
                    while insert_idx > 0 and task_lines[insert_idx - 1].strip() == '':
                        insert_idx -= 1
                    task_lines.insert(insert_idx,
                        ' ' * (task_indent + 2) + 'when: ansible_virtualization_type != "docker"')

            new_lines.extend(task_lines)
            i = j
        else:
            new_lines.append(line)
            i += 1

    new_content = '\n'.join(new_lines)
    if new_content != original:
        with open(filepath, 'w') as f:
            f.write(new_content)
        return True
    return False


# === TASKS ===

fixes = {
    # common/tasks/main.yml
    'roles/common/tasks/main.yml': [
        'Configurer la locale fr_FR.UTF-8',
        'Configurer le hostname du serveur',
        'Mettre à jour /etc/hosts avec le hostname',
    ],
    # security/tasks/main.yml
    'roles/security/tasks/main.yml': [
        'community.general.ufw:',
        'ansible.posix.sysctl:',
    ],
    # hardening/tasks/main.yml
    'roles/hardening/tasks/main.yml': [
        'ansible.posix.sysctl:',
        'Créer le fichier swap',
        'Ajouter le swap dans fstab',
        'Vérifier si le swap est actif',
    ],
}

print("[FIX] 2-7: Ajout conditions Docker aux tasks incompatibles")

for filepath, patterns in fixes.items():
    if os.path.exists(filepath):
        if add_docker_when(filepath, patterns):
            print(f'  ✅ {filepath}')
        else:
            print(f'  ⏭️  {filepath} (déjà corrigé ou pas de match)')

# === HANDLERS ===
# Vérifier que les handlers ont aussi le when:
print("[FIX] Vérification handlers...")

handler_files = glob.glob('roles/*/handlers/main.yml')
for hf in handler_files:
    if os.path.exists(hf):
        if add_docker_when(hf, ['ansible.builtin.service:']):
            print(f'  ✅ {hf}')

PYFIX

success "Tous les fixes appliqués"

# ──────────────────────────────────────────────
# Vérification finale
# ──────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════"
echo "  Vérification rapide"
echo "═══════════════════════════════════════════"
echo ""
echo "Tasks service sans condition Docker :"
grep -rn "ansible.builtin.service:" roles/*/tasks/main.yml roles/*/handlers/main.yml | while read line; do
  file=$(echo "$line" | cut -d: -f1)
  lineno=$(echo "$line" | cut -d: -f2)
  # Chercher when: dans les 5 lignes suivantes
  if ! sed -n "$((lineno+1)),$((lineno+5))p" "$file" | grep -q "ansible_virtualization_type"; then
    echo "  ⚠️  $line"
  fi
done

echo ""
echo "Modules incompatibles Docker sans condition :"
for pattern in "community.general.ufw:" "ansible.posix.sysctl:" "community.general.locale_gen:" "ansible.builtin.hostname:"; do
  grep -rn "$pattern" roles/*/tasks/main.yml | while read line; do
    file=$(echo "$line" | cut -d: -f1)
    lineno=$(echo "$line" | cut -d: -f2)
    if ! sed -n "$((lineno-3)),$((lineno+5))p" "$file" | grep -q "ansible_virtualization_type"; then
      echo "  ⚠️  $line"
    fi
  done
done

echo ""
echo "passlib dans requirements-dev.txt :"
grep "passlib" requirements-dev.txt && echo "  ✅" || echo "  ⚠️  MANQUANT"

echo ""
echo "═══════════════════════════════════════════"
echo "  Prochaines étapes :"
echo "  1. make lint"
echo "  2. cd roles/monit && molecule test"
echo "  3. git add -A && git commit && git push"
echo "═══════════════════════════════════════════"
