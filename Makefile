# ============================================================
# Makefile — Seko-VPN : lint, molecule, wizard
# ============================================================
SHELL := /bin/bash
ROOT_DIR := $(shell pwd)
VENV := .venv
PYTHON := $(ROOT_DIR)/$(VENV)/bin/python
PIP := $(ROOT_DIR)/$(VENV)/bin/pip
MOLECULE := $(ROOT_DIR)/$(VENV)/bin/molecule
ANSIBLE_LINT := $(ROOT_DIR)/$(VENV)/bin/ansible-lint
YAMLLINT := $(ROOT_DIR)/$(VENV)/bin/yamllint
ANSIBLE_GALAXY := $(ROOT_DIR)/$(VENV)/bin/ansible-galaxy

# Liste des 14 rôles dans l'ordre d'exécution
ROLES := common security docker hardening caddy headscale headplane vaultwarden portainer zerobyte uptime_kuma monit alloy telegram_bot

.PHONY: help venv lint molecule role clean wizard wsl-repair

help: ## Affiche cette aide
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

venv: ## Créer le virtualenv et installer les dépendances
	python3 -m venv $(VENV)
	$(PIP) install --upgrade pip
	$(PIP) install -r requirements-dev.txt
	$(ANSIBLE_GALAXY) collection install -r requirements.yml --force
	@echo "✅ Virtualenv prêt : source $(VENV)/bin/activate"

lint: ## Lancer yamllint + ansible-lint
	$(YAMLLINT) -c .yamllint .
	$(ANSIBLE_LINT)
	@echo "✅ Lint OK"

molecule: ## Tester tous les rôles avec Molecule
	@for role in $(ROLES); do \
		echo "══════ Testing role: $$role ══════"; \
		cd $(ROOT_DIR)/roles/$$role && $(MOLECULE) test || exit 1; \
		cd $(ROOT_DIR); \
	done
	@echo "✅ Tous les rôles testés"

role: ## Tester un rôle spécifique (usage: make role ROLE=common)
ifndef ROLE
	$(error ROLE non défini. Usage: make role ROLE=common)
endif
	cd $(ROOT_DIR)/roles/$(ROLE) && $(MOLECULE) test

clean: ## Nettoyer les conteneurs Molecule orphelins
	@for role in $(ROLES); do \
		cd $(ROOT_DIR)/roles/$$role && $(MOLECULE) destroy 2>/dev/null || true; \
		cd $(ROOT_DIR); \
	done
	@echo "✅ Nettoyage terminé"

wizard: ## Lancer le wizard de configuration interactif
	./scripts/wizard.sh

wsl-repair: ## Corriger DNS/systemd WSL2
	$(ROOT_DIR)/$(VENV)/bin/ansible-playbook playbooks/wsl-repair.yml --connection local
