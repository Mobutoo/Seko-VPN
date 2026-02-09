#!/usr/bin/env bash
# ============================================================
# bootstrap-vps.sh — Préparation initiale d'un VPS Debian
# Usage : ./scripts/bootstrap-vps.sh <IP> <USERNAME> <SSH_PUBKEY_PATH>
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${CYAN}ℹ️  $*${NC}"; }
success() { echo -e "${GREEN}✅ $*${NC}"; }
warn()    { echo -e "${YELLOW}⚠️  $*${NC}"; }
error()   { echo -e "${RED}❌ $*${NC}" >&2; }

if [[ $# -lt 3 ]]; then
  echo -e "\n${BOLD}Usage :${NC} $0 <IP_VPS> <USERNAME> <SSH_PUBKEY_PATH>"
  echo -e "${BOLD}Exemple :${NC} $0 203.0.113.10 srvadmin ~/.ssh/id_ed25519.pub\n"
  exit 1
fi

VPS_IP="$1"; NEW_USER="$2"; PUBKEY_PATH="$3"
SSH_PORT="${SSH_PORT:-22}"; SSH_USER="${SSH_USER:-root}"

[[ ! -f "$PUBKEY_PATH" ]] && { error "Clé introuvable : $PUBKEY_PATH"; exit 1; }
PUBKEY=$(cat "$PUBKEY_PATH")
[[ ! "$PUBKEY" =~ ^ssh-(ed25519|rsa|ecdsa) ]] && { error "Clé SSH invalide."; exit 1; }
PASSWORD=$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9!@$%&*+=' | head -c 24)

echo -e "\n${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║         Bootstrap VPS — Seko-VPN                 ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}\n"
info "VPS : ${SSH_USER}@${VPS_IP}:${SSH_PORT}"; info "Utilisateur : $NEW_USER"
echo -n "Continuer ? (o/N) "; read -r answer
[[ ! "$answer" =~ ^[oOyY]$ ]] && { echo "Annulé."; exit 0; }

SSH_CMD="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p $SSH_PORT ${SSH_USER}@${VPS_IP}"

info "Connexion au VPS..."
$SSH_CMD "echo ok" &>/dev/null || { error "Connexion impossible."; exit 1; }
success "Connexion établie"

info "Mise à jour du système..."
$SSH_CMD "apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq" 2>/dev/null
success "Système mis à jour"

info "Installation des paquets de base..."
$SSH_CMD "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq sudo curl wget gnupg ca-certificates" 2>/dev/null
success "Paquets installés"

info "Création de l'utilisateur '$NEW_USER'..."
$SSH_CMD bash <<REMOTE_SCRIPT
set -euo pipefail
if id "$NEW_USER" &>/dev/null; then echo "L'utilisateur $NEW_USER existe déjà."
else useradd -m -s /bin/bash -G sudo "$NEW_USER"; fi
echo "${NEW_USER}:${PASSWORD}" | chpasswd
echo "${NEW_USER} ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/${NEW_USER}"
chmod 0440 "/etc/sudoers.d/${NEW_USER}"
USER_HOME=\$(eval echo ~${NEW_USER})
mkdir -p "\${USER_HOME}/.ssh"
echo "${PUBKEY}" > "\${USER_HOME}/.ssh/authorized_keys"
chmod 700 "\${USER_HOME}/.ssh"; chmod 600 "\${USER_HOME}/.ssh/authorized_keys"
chown -R "${NEW_USER}:${NEW_USER}" "\${USER_HOME}/.ssh"
REMOTE_SCRIPT
success "Utilisateur '$NEW_USER' configuré"

info "Test de connexion avec ${NEW_USER}@${VPS_IP}..."
SSH_TEST="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p $SSH_PORT -i ${PUBKEY_PATH%.pub} ${NEW_USER}@${VPS_IP}"
if $SSH_TEST "sudo whoami" 2>/dev/null | grep -q "root"; then success "Connexion SSH + sudo OK"
else warn "Le test a échoué. Vérifiez manuellement."; fi

echo -e "\n${BOLD}  Bootstrap terminé !${NC}"
echo -e "  ${BOLD}Utilisateur :${NC} $NEW_USER"
echo -e "  ${BOLD}Mot de passe :${NC} $PASSWORD"
echo -e "  ${YELLOW}⚠️  Notez ce mot de passe !${NC}\n"
