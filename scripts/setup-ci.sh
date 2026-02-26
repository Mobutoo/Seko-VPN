#!/usr/bin/env bash
# ============================================================
# setup-ci.sh — Installation de l'environnement CI local
# ============================================================
set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${CYAN}ℹ️  $*${NC}"; }
success() { echo -e "${GREEN}✅ $*${NC}"; }

echo -e "\n${BOLD}Installation de l'environnement CI local${NC}\n"

# Python venv
if [[ ! -d .venv ]]; then
    info "Création du virtualenv Python..."
    python3 -m venv .venv
    success "Virtualenv créé"
fi

info "Installation des dépendances Python..."
.venv/bin/pip install --upgrade pip
.venv/bin/pip install -r requirements-dev.txt
success "Dépendances Python installées"

info "Installation des collections Ansible..."
.venv/bin/ansible-galaxy collection install -r requirements.yml --force
success "Collections Ansible installées"

# Docker
if ! command -v docker &>/dev/null; then
    info "Installation de Docker..."
    set +e
    curl -fsSL https://get.docker.com | sh
    set -e
    sudo usermod -aG docker "$USER"
    success "Docker installé"
else
    success "Docker déjà installé"
fi

echo -e "\n${BOLD}✅ Environnement CI prêt !${NC}"
echo -e "  Activez le venv : ${CYAN}source .venv/bin/activate${NC}"
echo -e "  Testez : ${CYAN}make lint${NC}\n"
