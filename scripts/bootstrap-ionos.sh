#!/usr/bin/env bash
# ============================================================
# bootstrap-ionos.sh — Préparation VPS IONOS Debian 13 minimal
# Adapté pour l'image minimale IONOS (dépôts incomplets)
#
# Usage : ./scripts/bootstrap-ionos.sh <IP> <USERNAME> <SSH_PUBKEY_PATH> [HOSTNAME]
#
# CLÉS SSH :
#   Ce script attend en argument le chemin vers la CLÉ PUBLIQUE DE DÉPLOIEMENT
#   (celle de votre machine locale, ex: ~/.ssh/seko-vpn-deploy.pub).
#   Cette clé sera copiée sur le VPS pour permettre la connexion SSH
#   sans mot de passe depuis votre machine locale et depuis le pipeline CI/CD.
#
# Ce script :
#   1. Se connecte au VPS via root + mot de passe IONOS (première connexion)
#   2. Corrige les dépôts Debian 13 (image minimale IONOS)
#   3. Installe les paquets de base (dont lsb-release)
#   4. Crée l'utilisateur avec la clé publique + sudo NOPASSWD
#   5. Change le hostname du VPS
#   6. Prépare le VPS pour Ansible
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${CYAN}ℹ️  $*${NC}"; }
success() { echo -e "${GREEN}✅ $*${NC}"; }
warn()    { echo -e "${YELLOW}⚠️  $*${NC}"; }
error()   { echo -e "${RED}❌ $*${NC}" >&2; }

if [[ $# -lt 3 ]]; then
  echo -e "\n${BOLD}Usage :${NC} $0 <IP_VPS> <USERNAME> <SSH_PUBKEY_PATH> [HOSTNAME]"
  echo -e ""
  echo -e "${BOLD}Arguments :${NC}"
  echo -e "  IP_VPS           IP publique du VPS IONOS"
  echo -e "  USERNAME         Nom de l'utilisateur à créer (ex: srvadmin)"
  echo -e "  SSH_PUBKEY_PATH  Chemin de la clé publique ${BOLD}locale${NC} de déploiement"
  echo -e "                   (ex: ~/.ssh/seko-vpn-deploy.pub)"
  echo -e "  HOSTNAME         Nom du serveur (défaut: seko-vpn-01)"
  echo -e ""
  echo -e "${BOLD}Prérequis :${NC}"
  echo -e "  1. Générer une clé SSH dédiée sur votre machine locale :"
  echo -e "     ${CYAN}ssh-keygen -t ed25519 -f ~/.ssh/seko-vpn-deploy -C \"seko-vpn-deploy\"${NC}"
  echo -e "  2. Avoir le mot de passe root IONOS (fourni par IONOS à la création du VPS)"
  echo -e ""
  echo -e "${BOLD}Exemple :${NC}"
  echo -e "  $0 203.0.113.10 srvadmin ~/.ssh/seko-vpn-deploy.pub seko-vpn-01"
  echo -e ""
  exit 1
fi

VPS_IP="$1"; NEW_USER="$2"; PUBKEY_PATH="$3"
NEW_HOSTNAME="${4:-seko-vpn-01}"
SSH_PORT="${SSH_PORT:-22}"; SSH_USER="${SSH_USER:-root}"

# ── Validation de la clé publique locale ─────────────────────
[[ ! -f "$PUBKEY_PATH" ]] && { error "Clé publique introuvable : $PUBKEY_PATH"; echo -e "  Générez-la d'abord : ${CYAN}ssh-keygen -t ed25519 -f ${PUBKEY_PATH%.pub}${NC}"; exit 1; }
PUBKEY=$(cat "$PUBKEY_PATH")
[[ ! "$PUBKEY" =~ ^ssh-(ed25519|rsa|ecdsa) ]] && { error "Le fichier ne contient pas une clé SSH valide."; exit 1; }

# Vérifier que la clé privée correspondante existe
PRIVKEY_PATH="${PUBKEY_PATH%.pub}"
if [[ ! -f "$PRIVKEY_PATH" ]]; then
  warn "Clé privée correspondante non trouvée : $PRIVKEY_PATH"
  warn "Le test de connexion final risque d'échouer."
fi

PASSWORD=$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9!@$%&*+=' | head -c 24)

echo -e "\n${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║    Bootstrap VPS IONOS — Debian 13 minimal       ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}\n"
info "VPS            : ${SSH_USER}@${VPS_IP}:${SSH_PORT}"
info "Utilisateur    : $NEW_USER"
info "Hostname cible : $NEW_HOSTNAME"
info "Clé publique   : $PUBKEY_PATH (locale → copiée vers le VPS)"
echo ""
echo -e "  ${YELLOW}⚠️  La première connexion utilise root + mot de passe IONOS.${NC}"
echo -e "  ${YELLOW}   Après le bootstrap, la connexion SSH se fera avec la clé.${NC}"
echo ""
echo -n "Continuer ? (o/N) "; read -r answer
[[ ! "$answer" =~ ^[oOyY]$ ]] && { echo "Annulé."; exit 0; }

#Fix utilisataion de SSH ControlMaster
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -p $SSH_PORT"
CTRL_SOCKET="/tmp/bootstrap-ssh-$$"

# Ouvrir une connexion SSH persistante (un seul mot de passe)
info "Ouverture de la connexion SSH (un seul mot de passe)..."
ssh $SSH_OPTS -o ControlMaster=yes -o ControlPath="$CTRL_SOCKET" \
    -o ControlPersist=300 -fN ${SSH_USER}@${VPS_IP} \
    || { error "Connexion impossible."; exit 1; }
success "Connexion établie (multiplexée)"

# Fonction SSH réutilisant la connexion existante (plus de mot de passe)
SSH_CMD="ssh $SSH_OPTS -o ControlPath=$CTRL_SOCKET ${SSH_USER}@${VPS_IP}"
SCP_CMD="scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 -P $SSH_PORT -o ControlPath=$CTRL_SOCKET"

# Fermer la connexion à la fin du script
trap 'ssh -o ControlPath=$CTRL_SOCKET -O exit ${SSH_USER}@${VPS_IP} 2>/dev/null || true; rm -f $CTRL_SOCKET' EXIT

info "Connexion au VPS (root + mot de passe IONOS)..."
$SSH_CMD "echo ok" &>/dev/null || { error "Connexion impossible. Vérifiez l'IP et le mot de passe root IONOS."; exit 1; }
success "Connexion établie"

# ──────────────────────────────────────────────
# Étape 1 : Corriger les dépôts Debian 13 minimal
# ──────────────────────────────────────────────
info "Correction des dépôts Debian 13 minimal..."
$SSH_CMD bash <<'FIX_REPOS'
set -euo pipefail

if ! apt-cache policy lsb-release 2>/dev/null | grep -q "Candidate:"; then
  echo "🔧 Dépôts incomplets détectés, correction..."

  cp /etc/apt/sources.list.d/debian.sources /etc/apt/sources.list.d/debian.sources.bak 2>/dev/null || true

  cat > /etc/apt/sources.list.d/debian.sources <<DCONF
Types: deb
URIs: http://deb.debian.org/debian
Suites: trixie trixie-updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://deb.debian.org/debian-security
Suites: trixie-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
DCONF

  echo "# Géré par bootstrap-ionos.sh — voir /etc/apt/sources.list.d/" > /etc/apt/sources.list
  apt-get update -qq
  echo "✅ Dépôts corrigés"
else
  echo "ℹ️  Dépôts déjà complets"
  apt-get update -qq
fi
FIX_REPOS
success "Dépôts Debian 13 vérifiés/corrigés"

# ──────────────────────────────────────────────
# Étape 2 : Mise à jour système + paquets de base
# ──────────────────────────────────────────────
info "Mise à jour du système..."
$SSH_CMD "DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq" 2>/dev/null
success "Système mis à jour"

info "Installation des paquets de base..."
$SSH_CMD "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  sudo curl wget gnupg ca-certificates apt-transport-https \
  python3 python3-pip lsb-release locales \
  git htop jq unzip rsync vim net-tools" 2>/dev/null
success "Paquets installés (dont lsb-release)"

# ──────────────────────────────────────────────
# Étape 3 : Changement du hostname
# ──────────────────────────────────────────────
info "Configuration du hostname → $NEW_HOSTNAME..."
$SSH_CMD bash <<HOSTNAME_SCRIPT
set -euo pipefail
OLD_HOSTNAME=\$(hostname)
if [ "\$OLD_HOSTNAME" != "$NEW_HOSTNAME" ]; then
  hostnamectl set-hostname "$NEW_HOSTNAME"
  sed -i "s/\$OLD_HOSTNAME/$NEW_HOSTNAME/g" /etc/hosts 2>/dev/null || true
  if ! grep -q "$NEW_HOSTNAME" /etc/hosts; then
    echo "127.0.1.1 $NEW_HOSTNAME" >> /etc/hosts
  fi
  echo "✅ Hostname changé : \$OLD_HOSTNAME → $NEW_HOSTNAME"
else
  echo "ℹ️  Hostname déjà correct"
fi
HOSTNAME_SCRIPT
success "Hostname configuré"

# ──────────────────────────────────────────────
# Étape 4 : Création de l'utilisateur + copie de la clé publique
# ──────────────────────────────────────────────
info "Vérification de l'utilisateur '$NEW_USER'..."
USER_EXISTS=$($SSH_CMD "id $NEW_USER &>/dev/null && echo yes || echo no")

if [[ "$USER_EXISTS" == "yes" ]]; then
  warn "L'utilisateur '$NEW_USER' existe déjà — mot de passe inchangé."
  PASSWORD="(inchangé — déjà configuré lors du premier bootstrap)"
else
  info "Création de l'utilisateur '$NEW_USER'..."
  $SSH_CMD bash <<CREATEUSER
set -euo pipefail
useradd -m -s /bin/bash -G sudo "$NEW_USER"
echo "${NEW_USER}:${PASSWORD}" | chpasswd
echo "${NEW_USER} ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/${NEW_USER}"
chmod 0440 "/etc/sudoers.d/${NEW_USER}"
CREATEUSER
  success "Utilisateur '$NEW_USER' créé"
fi

# Injection de la clé via scp (pas de pipe, pas de heredoc)
info "Copie de la clé publique locale vers le VPS via scp..."
$SSH_CMD "mkdir -p /home/$NEW_USER/.ssh && chmod 700 /home/$NEW_USER/.ssh"
$SCP_CMD "$PUBKEY_PATH" "${SSH_USER}@${VPS_IP}:/home/$NEW_USER/.ssh/authorized_keys"
$SSH_CMD "chmod 600 /home/$NEW_USER/.ssh/authorized_keys && chown -R $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh"
success "Clé SSH copiée via scp (fichier exact, aucune transformation)"

# ──────────────────────────────────────────────
# Étape 5 : Test de connexion avec la clé privée locale
# ──────────────────────────────────────────────
if [[ -f "$PRIVKEY_PATH" ]]; then
  info "Test de connexion : ${NEW_USER}@${VPS_IP} avec la clé locale ${PRIVKEY_PATH}..."
  SSH_TEST="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p $SSH_PORT -i ${PRIVKEY_PATH} ${NEW_USER}@${VPS_IP}"
  if $SSH_TEST "sudo whoami" 2>/dev/null | grep -q "root"; then
    success "Connexion SSH par clé + sudo OK"
  else
    warn "Le test a échoué. Vérifiez manuellement."
  fi
else
  warn "Clé privée $PRIVKEY_PATH absente, test de connexion ignoré."
fi

echo -e "\n${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║         Bootstrap IONOS terminé !                 ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo -e ""
echo -e "  ${BOLD}Utilisateur :${NC} $NEW_USER"
echo -e "  ${BOLD}Mot de passe :${NC} $PASSWORD  ${YELLOW}(à noter, utilisé par ansible-vault)${NC}"
echo -e "  ${BOLD}Hostname :${NC} $NEW_HOSTNAME"
echo -e "  ${BOLD}Clé SSH :${NC} $PUBKEY_PATH → copiée dans ~${NEW_USER}/.ssh/authorized_keys"
echo -e ""
echo -e "  ${CYAN}Prochaines étapes :${NC}"
echo -e "  ${BOLD}1.${NC} ./scripts/wizard.sh"
echo -e "  ${BOLD}2.${NC} git add -A && git commit && git push origin main"
echo -e "     → déclenche le pipeline CI/CD (lint → molecule → integration → deploy)"
echo -e ""
