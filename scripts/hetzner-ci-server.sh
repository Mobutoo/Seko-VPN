#!/usr/bin/env bash
# ============================================================
# hetzner-ci-server.sh — Gestion VM éphémère Hetzner pour CI
#
# Usage :
#   ./scripts/hetzner-ci-server.sh create [NAME]
#   ./scripts/hetzner-ci-server.sh destroy [NAME]
#   ./scripts/hetzner-ci-server.sh status [NAME]
#
# Prérequis : hcloud CLI + HCLOUD_TOKEN en variable d'env
#
# CLÉS SSH :
#   Ce script génère une clé SSH ÉPHÉMÈRE dans /tmp/ pour la VM CI.
#   Cette clé est supprimée avec la VM lors du destroy.
#   Elle n'a rien à voir avec la clé de déploiement (~/.ssh/seko-vpn-deploy).
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${CYAN}ℹ️  $*${NC}"; }
success() { echo -e "${GREEN}✅ $*${NC}"; }
warn()    { echo -e "${YELLOW}⚠️  $*${NC}"; }
error()   { echo -e "${RED}❌ $*${NC}" >&2; }

# ── Configuration (modifiable si la gamme Hetzner change) ────
SERVER_TYPE="${HCLOUD_SERVER_TYPE:-cx23}"
IMAGE="${HCLOUD_IMAGE:-debian-13}"
DATACENTERS="${HCLOUD_DATACENTERS:-fsn1 nbg1 hel1}"

ACTION="${1:-help}"
SERVER_NAME="${2:-seko-vpn-ci-$(date +%s)}"

usage() {
  echo -e "\n${BOLD}Usage :${NC}"
  echo -e "  $0 create  [NAME]   Créer une VM éphémère (type: $SERVER_TYPE)"
  echo -e "  $0 destroy [NAME]   Détruire une VM + clé SSH éphémère"
  echo -e "  $0 status  [NAME]   Afficher l'état de la VM"
  echo -e "\n${BOLD}Variables d'env :${NC}"
  echo -e "  HCLOUD_TOKEN          Token API Hetzner (obligatoire)"
  echo -e "  HCLOUD_SERVER_TYPE    Type de serveur (défaut: $SERVER_TYPE)"
  echo -e "  HCLOUD_IMAGE          Image OS (défaut: $IMAGE)"
  echo -e "  HCLOUD_DATACENTERS    Datacenters avec fallback (défaut: $DATACENTERS)"
  echo -e ""
}

check_prerequisites() {
  if ! command -v hcloud &>/dev/null; then
    error "hcloud CLI non trouvé. Installation :"
    echo -e "  curl -fsSL https://github.com/hetznercloud/cli/releases/latest/download/hcloud-linux-amd64.tar.gz | tar xz -C /usr/local/bin hcloud"
    exit 1
  fi
  if [[ -z "${HCLOUD_TOKEN:-}" ]]; then
    error "HCLOUD_TOKEN non défini."
    echo -e "  export HCLOUD_TOKEN='votre-token-hetzner'"
    exit 1
  fi
}

create_server() {
  check_prerequisites
  info "Création du serveur CI : $SERVER_NAME (type: $SERVER_TYPE)"

  # Générer une clé SSH éphémère (pas la clé de déploiement !)
  local key_file="/tmp/ci-key-${SERVER_NAME}"
  if [[ ! -f "$key_file" ]]; then
    ssh-keygen -t ed25519 -f "$key_file" -N "" -C "ci-ephemeral-${SERVER_NAME}" >/dev/null 2>&1
    info "Clé SSH éphémère générée : $key_file (temporaire, sera supprimée au destroy)"
  fi

  hcloud ssh-key create --name "$SERVER_NAME" --public-key "$(cat "${key_file}.pub")" 2>/dev/null || true

  local created=false
  for dc in $DATACENTERS; do
    info "Tentative de création dans $dc..."
    if hcloud server create \
      --name "$SERVER_NAME" \
      --type "$SERVER_TYPE" \
      --image "$IMAGE" \
      --datacenter "$dc" \
      --ssh-key "$SERVER_NAME" \
      --label "purpose=ci" 2>&1; then
      created=true
      success "Serveur créé dans $dc"
      break
    else
      warn "Échec dans $dc, fallback..."
    fi
  done

  if [ "$created" = false ]; then
    error "Impossible de créer le serveur dans aucun datacenter"
    exit 1
  fi

  local ip
  ip=$(hcloud server ip "$SERVER_NAME")
  success "Serveur CI prêt :"
  echo -e "  ${BOLD}IP :${NC} $ip"
  echo -e "  ${BOLD}SSH :${NC} ssh -i $key_file root@$ip"
  echo -e "  ${BOLD}Détruire :${NC} $0 destroy $SERVER_NAME"

  info "Attente SSH..."
  for i in $(seq 1 20); do
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$key_file" root@"$ip" "echo ok" 2>/dev/null; then
      success "SSH prêt"
      return 0
    fi
    sleep 5
  done
  warn "SSH pas encore prêt après 100s."
}

destroy_server() {
  check_prerequisites
  info "Destruction du serveur CI : $SERVER_NAME"
  hcloud server delete "$SERVER_NAME" 2>/dev/null && success "Serveur supprimé" || warn "Serveur non trouvé"
  hcloud ssh-key delete "$SERVER_NAME" 2>/dev/null && success "Clé SSH Hetzner supprimée" || warn "Clé SSH non trouvée"
  rm -f "/tmp/ci-key-${SERVER_NAME}" "/tmp/ci-key-${SERVER_NAME}.pub" 2>/dev/null || true
  success "Nettoyage terminé (VM + clé éphémère supprimées)"
}

status_server() {
  check_prerequisites
  if hcloud server describe "$SERVER_NAME" 2>/dev/null; then
    success "Serveur trouvé"
  else
    info "Aucun serveur nommé '$SERVER_NAME'"
  fi
}

case "$ACTION" in
  create)  create_server ;;
  destroy) destroy_server ;;
  status)  status_server ;;
  *)       usage ;;
esac
