# OpenSOP — convenience targets for day-to-day operations.
# Prerequisites: Docker + docker compose v2.
# All secrets live in .env — never commit that file.
#
# Run `make help` to see all targets.

.PHONY: help setup up down restart logs status ps shell \
        rotate-token rotate-master-key console health \
        backup uninstall

# ─── Default target ──────────────────────────────────────────────────────────
.DEFAULT_GOAL := help

help:
	@echo ""
	@echo "OpenSOP — common operations"
	@echo ""
	@echo "  make setup             first-time setup (runs scripts/install.sh)"
	@echo "  make up                start services"
	@echo "  make down              stop services"
	@echo "  make restart           restart app container only"
	@echo "  make logs              tail app logs (last 200 lines)"
	@echo "  make status            show container status"
	@echo "  make shell             open a shell in the app container"
	@echo "  make console           open a Rails console"
	@echo "  make health            check /up health endpoint"
	@echo "  make backup            pg_dump database to ./backups/"
	@echo "  make rotate-token      generate a new OPENSOP_API_TOKEN"
	@echo "  make rotate-master-key regenerate RAILS_MASTER_KEY + SECRET_KEY_BASE"
	@echo "  make uninstall         stop + remove containers, volumes, and .env"
	@echo ""

# ─── First-time setup ─────────────────────────────────────────────────────────
setup:
	@bash scripts/install.sh

# ─── Service lifecycle ────────────────────────────────────────────────────────
up:
	@docker compose up -d
	@$(MAKE) --no-print-directory status

down:
	@docker compose down

restart:
	@docker compose restart app

# ─── Observability ────────────────────────────────────────────────────────────
logs:
	@docker compose logs -f --tail=200 app

status:
	@docker compose ps

# ─── Access ───────────────────────────────────────────────────────────────────
shell:
	@docker compose exec app /bin/bash

console:
	@docker compose exec app /rails/bin/rails console

# ─── Health check ─────────────────────────────────────────────────────────────
health:
	@PORT=$$(grep '^OPENSOP_PORT=' .env 2>/dev/null | cut -d= -f2); \
	PORT=$${PORT:-3000}; \
	echo "Checking http://localhost:$$PORT/up ..."; \
	curl -fsS --max-time 5 "http://localhost:$$PORT/up" \
	  && echo "  [ok]    healthy" \
	  || { echo "  [fail]  not responding — try: docker compose logs app"; exit 1; }

# ─── Secret rotation ──────────────────────────────────────────────────────────
rotate-token:
	@command -v openssl >/dev/null 2>&1 || { echo "openssl not found"; exit 1; }
	@[[ -f .env ]] || { echo ".env not found — run 'make setup' first"; exit 1; }
	@NEW=$$(openssl rand -hex 32); \
	echo ""; \
	echo "  New OPENSOP_API_TOKEN: $$NEW"; \
	echo ""; \
	if [[ "$$(uname)" == "Darwin" ]]; then \
	  sed -i '' -E "s|^OPENSOP_API_TOKEN=.*|OPENSOP_API_TOKEN=$$NEW|" .env; \
	else \
	  sed -i -E "s|^OPENSOP_API_TOKEN=.*|OPENSOP_API_TOKEN=$$NEW|" .env; \
	fi; \
	docker compose restart app; \
	echo "  Token rotated and app restarted."; \
	echo "  Update your API client: X-SOP-Token: $$NEW"

rotate-master-key:
	@echo ""
	@echo "  WARNING: this regenerates RAILS_MASTER_KEY + SECRET_KEY_BASE."
	@echo "  All existing sessions will be invalidated."
	@echo ""
	@printf "  Continue? [y/N] "; \
	read -r ans </dev/tty; \
	[ "$$ans" = "y" ] || { echo "Aborted."; exit 0; }
	@command -v openssl >/dev/null 2>&1 || { echo "openssl not found"; exit 1; }
	@[[ -f .env ]] || { echo ".env not found — run 'make setup' first"; exit 1; }
	@NEW_MASTER=$$(openssl rand -hex 32); \
	NEW_SECRET=$$(openssl rand -hex 64); \
	if [[ "$$(uname)" == "Darwin" ]]; then \
	  sed -i '' -E \
	    -e "s|^RAILS_MASTER_KEY=.*|RAILS_MASTER_KEY=$$NEW_MASTER|" \
	    -e "s|^SECRET_KEY_BASE=.*|SECRET_KEY_BASE=$$NEW_SECRET|" .env; \
	else \
	  sed -i -E \
	    -e "s|^RAILS_MASTER_KEY=.*|RAILS_MASTER_KEY=$$NEW_MASTER|" \
	    -e "s|^SECRET_KEY_BASE=.*|SECRET_KEY_BASE=$$NEW_SECRET|" .env; \
	fi; \
	rm -f config/credentials.yml.enc; \
	docker compose down && docker compose up -d; \
	echo "  Master key and secret rotated. Stack restarted."

# ─── Database backup ──────────────────────────────────────────────────────────
backup:
	@mkdir -p backups
	@DATE=$$(date -u +%Y%m%d-%H%M%S); \
	OUTFILE="backups/opensop-$$DATE.sql"; \
	docker compose exec -T db pg_dump \
	  -U $${POSTGRES_USER:-opensop} \
	  $${POSTGRES_DB:-opensop_production} \
	  > "$$OUTFILE"; \
	echo "  Backup written to $$OUTFILE"

# ─── Uninstall ────────────────────────────────────────────────────────────────
uninstall:
	@echo ""
	@echo "  This will STOP and REMOVE: containers, named volumes, and .env."
	@echo "  The cloned repo directory itself will NOT be deleted."
	@echo ""
	@printf "  Are you sure? [y/N] "; \
	read -r ans </dev/tty; \
	[ "$$ans" = "y" ] || { echo "Aborted."; exit 0; }
	@docker compose down -v
	@rm -f .env
	@echo "  Uninstalled. Run 'make setup' to start fresh."
