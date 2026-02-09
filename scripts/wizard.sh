#!/usr/bin/env bash
# ============================================================
# wizard.sh — Configuration interactive du projet Seko-VPN
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

header()  { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════${NC}"; echo -e "${BOLD}  $1${NC}"; echo -e "${BOLD}${CYAN}══════════════════════════════════════${NC}\n"; }
success() { echo -e "  ${GREEN}✅ $1${NC}"; }
info()    { echo -e "  ${CYAN}ℹ️  $1${NC}"; }
warn()    { echo -e "  ${YELLOW}⚠️  $1${NC}"; }
error()   { echo -e "  ${RED}❌ $1${NC}"; }

ask() {
    local prompt="$1" default="${2:-}" result
    if [[ -n "$default" ]]; then
        echo -ne "  ${BOLD}$prompt${NC} [${CYAN}$default${NC}] : " >&2; read -r result
        echo "${result:-$default}"
    else
        echo -ne "  ${BOLD}$prompt${NC} : " >&2; read -r result
        while [[ -z "$result" ]]; do error "Ce champ est obligatoire" >&2; echo -ne "  ${BOLD}$prompt${NC} : " >&2; read -r result; done
        echo "$result"
    fi
}

ask_secret() {
    local prompt="$1" result
    echo -ne "  ${BOLD}$prompt${NC} : " >&2; read -rs result; echo "" >&2
    while [[ -z "$result" ]]; do error "Ce champ est obligatoire" >&2; echo -ne "  ${BOLD}$prompt${NC} : " >&2; read -rs result; echo "" >&2; done
    echo "$result"
}

check_prerequisites() {
    header "Vérification des prérequis"
    local missing=false
    if ! command -v ansible-vault &>/dev/null; then error "ansible-vault non trouvé"; missing=true; else success "ansible-vault trouvé"; fi
    if ! command -v openssl &>/dev/null; then error "openssl non trouvé"; missing=true; else success "openssl trouvé"; fi
    if $missing; then error "Prérequis manquants."; exit 1; fi
}

check_existing_files() {
    local vars_file="inventory/group_vars/all/vars.yml" vault_file="inventory/group_vars/all/vault.yml" hosts_file="inventory/hosts.yml"
    if [[ -f "$vars_file" ]] || [[ -f "$vault_file" ]] || [[ -f "$hosts_file" ]]; then
        warn "Des fichiers de configuration existent déjà :"
        [[ -f "$vars_file" ]] && info "  $vars_file"; [[ -f "$vault_file" ]] && info "  $vault_file"; [[ -f "$hosts_file" ]] && info "  $hosts_file"
        echo ""; echo -ne "  ${BOLD}Écraser les fichiers existants ? (o/N)${NC} : "; read -r overwrite
        if [[ ! "$overwrite" =~ ^[oOyY]$ ]]; then info "Annulé."; exit 0; fi
    fi
}

collect_info() {
    header "Informations du serveur"
    SERVER_IP=$(ask "IP du VPS" ""); SYSTEM_USER=$(ask "Nom d'utilisateur système" "srvadmin")
    SSH_PUBKEY_PATH=$(ask "Chemin de la clé SSH publique" "$HOME/.ssh/id_ed25519.pub")
    [[ ! -f "$SSH_PUBKEY_PATH" ]] && warn "La clé $SSH_PUBKEY_PATH n'existe pas."
    SSH_PUBKEY_CONTENT=""; [[ -f "$SSH_PUBKEY_PATH" ]] && SSH_PUBKEY_CONTENT=$(cat "$SSH_PUBKEY_PATH")

    header "Configuration des domaines"
    DOMAIN=$(ask "Nom de domaine principal (ex: example.com)" ""); info "Les sous-domaines seront déduits automatiquement."; echo ""
    SUB_HEADSCALE=$(ask "Sous-domaine Headscale" "hs"); SUB_HEADPLANE=$(ask "Sous-domaine Headplane" "nga")
    SUB_VAULTWARDEN=$(ask "Sous-domaine Vaultwarden" "vault"); SUB_PORTAINER=$(ask "Sous-domaine Portainer" "portainer")
    SUB_ZEROBYTE=$(ask "Sous-domaine Zerobyte" "zb"); SUB_UPTIME_KUMA=$(ask "Sous-domaine Uptime Kuma" "status")
    echo ""; info "Domaines configurés :"
    for svc in HEADSCALE HEADPLANE VAULTWARDEN PORTAINER ZEROBYTE UPTIME_KUMA; do
        var="SUB_${svc}"; info "  ${svc,,} : ${!var}.${DOMAIN}"; done

    header "Configuration réseau et email"
    ACME_EMAIL=$(ask "Email ACME (Let's Encrypt)" "admin@${DOMAIN}"); SSH_PORT=$(ask "Port SSH custom" "2222")

    header "Configuration Telegram"
    info "Créez un bot via @BotFather sur Telegram pour obtenir le token."
    TELEGRAM_TOKEN=$(ask "Token du bot Telegram"); TELEGRAM_CHAT_ID=$(ask "Chat ID Telegram")

    header "Identification serveur"
    SERVER_NAME=$(ask "Nom du serveur (pour le bot Telegram)" "seko-vpn-01")
}

generate_secrets() {
    header "Génération des secrets"
    SECRET_USER_PASSWORD=$(openssl rand -base64 24); success "Mot de passe utilisateur généré"
    SECRET_VW_ADMIN_TOKEN=$(openssl rand -base64 32); success "Token admin Vaultwarden généré"
    SECRET_HP_COOKIE=$(openssl rand -base64 24 | head -c 32); success "Cookie secret Headplane généré (32 chars)"
    SECRET_ZB_APP_SECRET=$(openssl rand -hex 32); success "App secret Zerobyte généré (64 hex)"
    SECRET_MONIT_PASSWORD=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 16); success "Mot de passe Monit généré (alphanum, 16 chars)"
}

generate_vars() {
    header "Génération de vars.yml"; mkdir -p inventory/group_vars/all
    cat > inventory/group_vars/all/vars.yml << EOF
---
# vars.yml — Généré par wizard.sh le $(date +%Y-%m-%d)
server_ip: "${SERVER_IP}"
system_user: "${SYSTEM_USER}"
system_user_ssh_pubkey: "${SSH_PUBKEY_CONTENT}"
domain_headscale: "${SUB_HEADSCALE}.${DOMAIN}"
domain_headplane: "${SUB_HEADPLANE}.${DOMAIN}"
domain_vaultwarden: "${SUB_VAULTWARDEN}.${DOMAIN}"
domain_portainer: "${SUB_PORTAINER}.${DOMAIN}"
domain_zerobyte: "${SUB_ZEROBYTE}.${DOMAIN}"
domain_uptime_kuma: "${SUB_UPTIME_KUMA}.${DOMAIN}"
acme_email: "${ACME_EMAIL}"
ssh_custom_port: ${SSH_PORT}
ci_mode: false
headscale_version: "0.26.0"
vaultwarden_version: "1.35.1-alpine"
portainer_version: "lts"
zerobyte_version: "v0.25"
headplane_version: "latest"
uptime_kuma_version: "latest"
base_deploy_path: "/opt/services"
headscale_data_path: "{{ base_deploy_path }}/headscale"
headplane_data_path: "{{ base_deploy_path }}/headplane"
vaultwarden_data_path: "{{ base_deploy_path }}/vaultwarden"
portainer_data_path: "{{ base_deploy_path }}/portainer"
zerobyte_data_path: "{{ base_deploy_path }}/zerobyte"
uptime_kuma_data_path: "{{ base_deploy_path }}/uptime-kuma"
caddy_data_path: "{{ base_deploy_path }}/caddy"
telegram_bot_path: "{{ base_deploy_path }}/telegram-bot"
monit_check_interval: 30
monit_containers:
  - headscale
  - headplane
  - vaultwarden
  - portainer
  - zerobyte
  - caddy
  - uptime-kuma
telegram_bot_server_name: "${SERVER_NAME}"
alloy_loki_url: ""
hardening_swap_size: "2G"
hardening_journal_max_use: "500M"
hardening_journal_max_retention: "30day"
EOF
    success "vars.yml généré"
}

generate_vault() {
    header "Génération de vault.yml"
    cat > inventory/group_vars/all/vault.yml << EOF
---
vault_system_user_password: "${SECRET_USER_PASSWORD}"
vault_vaultwarden_admin_token: "${SECRET_VW_ADMIN_TOKEN}"
vault_headplane_cookie_secret: "${SECRET_HP_COOKIE}"
vault_zerobyte_app_secret: "${SECRET_ZB_APP_SECRET}"
vault_monit_password: "${SECRET_MONIT_PASSWORD}"
vault_telegram_bot_token: "${TELEGRAM_TOKEN}"
vault_telegram_chat_id: "${TELEGRAM_CHAT_ID}"
EOF
    success "vault.yml généré (non chiffré)"
}

generate_hosts() {
    header "Génération de hosts.yml"
    cat > inventory/hosts.yml << EOF
---
all:
  hosts:
    vps:
      ansible_host: ${SERVER_IP}
      ansible_user: ${SYSTEM_USER}
      ansible_port: 22
      ansible_ssh_private_key_file: ${SSH_PUBKEY_PATH%.pub}
EOF
    success "hosts.yml généré"
}

encrypt_vault() {
    header "Chiffrement de vault.yml"
    info "Choisissez un mot de passe pour ansible-vault."; echo ""
    ansible-vault encrypt inventory/group_vars/all/vault.yml
    success "vault.yml chiffré"
}

print_summary() {
    header "Configuration terminée !"
    echo -e "  ${BOLD}Fichiers générés :${NC}"
    echo "    📄 inventory/group_vars/all/vars.yml"
    echo "    🔒 inventory/group_vars/all/vault.yml (chiffré)"
    echo "    📄 inventory/hosts.yml"
    echo ""
    echo -e "  ${BOLD}Prochaines étapes :${NC}"
    echo "    1. Configurer les DNS (6 enregistrements A vers ${SERVER_IP})"
    echo "    2. ./scripts/bootstrap-vps.sh ${SERVER_IP} ${SYSTEM_USER} ${SSH_PUBKEY_PATH}"
    echo "    3. ansible-playbook playbooks/site.yml --ask-vault-pass"
    echo "    4. Vérifier : https://${SUB_UPTIME_KUMA}.${DOMAIN}"
    echo "    5. ansible-playbook playbooks/harden-ssh.yml --ask-vault-pass"
    echo ""
}

main() {
    echo -e "\n${BOLD}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║   Seko-VPN — Wizard de configuration V3         ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}\n"
    check_prerequisites; check_existing_files; collect_info; generate_secrets
    generate_vars; generate_vault; generate_hosts; encrypt_vault; print_summary
    success "Configuration terminée avec succès !"
}
main "$@"
