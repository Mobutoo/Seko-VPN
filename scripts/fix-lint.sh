#!/usr/bin/env bash
# ============================================================
# fix-lint.sh — Corrections ansible-lint automatisées
# ============================================================
set -euo pipefail

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

echo "🔧 Corrections ansible-lint automatisées"
[[ "$DRY_RUN" == "true" ]] && echo "  (mode dry-run, pas de modification)"

# Correction : handlers avec première lettre minuscule
echo "  → Vérification des handlers..."
find roles -path "*/handlers/main.yml" | while read -r f; do
    if grep -qP '^\s+- name: [a-z]' "$f" 2>/dev/null; then
        echo "    ⚠️  Handler minuscule détecté dans $f"
        if [[ "$DRY_RUN" == "false" ]]; then
            sed -i -E 's/(^\s+- name: )([a-z])/\1\u\2/' "$f"
            echo "    ✅ Corrigé"
        fi
    fi
done

# Correction : champ version dans docker-compose
echo "  → Vérification des docker-compose.yml..."
find roles -name "docker-compose.yml*" | while read -r f; do
    if grep -q '^version:' "$f" 2>/dev/null; then
        echo "    ⚠️  Champ 'version' trouvé dans $f"
        if [[ "$DRY_RUN" == "false" ]]; then
            sed -i '/^version:/d' "$f"
            echo "    ✅ Supprimé"
        fi
    fi
done

echo "✅ Terminé"
