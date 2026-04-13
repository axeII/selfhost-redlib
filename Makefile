SHELL := /bin/bash
INSTALL_DIR := /opt/redlib
WATCHDOG_BIN := /usr/local/bin/docker-watchdog.sh
SERVICE_FILE := /etc/systemd/system/docker-watchdog.service
MIN_SWAP_MB := 2048

.PHONY: check swap network install uninstall status help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

check: ## Verify prerequisites (docker, docker compose, curl)
	@echo "==> Checking prerequisites..."
	@# Must be root
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "ERROR: This must be run as root (use sudo make ...)"; \
		exit 1; \
	fi
	@echo "  [OK] Running as root"
	@# Docker
	@if ! command -v docker >/dev/null 2>&1; then \
		echo "  [FAIL] docker is not installed"; \
		echo "         Install: https://docs.docker.com/engine/install/"; \
		exit 1; \
	fi
	@echo "  [OK] docker found: $$(docker --version)"
	@# Docker daemon running
	@if ! docker info >/dev/null 2>&1; then \
		echo "  [FAIL] Docker daemon is not running"; \
		echo "         Start it with: systemctl start docker"; \
		exit 1; \
	fi
	@echo "  [OK] Docker daemon is running"
	@# Docker Compose (v2 plugin preferred, v1 standalone fallback)
	@if docker compose version >/dev/null 2>&1; then \
		echo "  [OK] docker compose (plugin): $$(docker compose version --short)"; \
	elif command -v docker-compose >/dev/null 2>&1; then \
		echo "  [OK] docker-compose (standalone): $$(docker-compose --version)"; \
	else \
		echo "  [FAIL] docker compose is not installed"; \
		echo "         Install the Docker Compose plugin: https://docs.docker.com/compose/install/"; \
		exit 1; \
	fi
	@# curl
	@if ! command -v curl >/dev/null 2>&1; then \
		echo "  [FAIL] curl is not installed (required by watchdog)"; \
		echo "         Install: apt install curl / yum install curl"; \
		exit 1; \
	fi
	@echo "  [OK] curl found"
	@echo "==> All prerequisites satisfied."

swap: ## Ensure swap is at least $(MIN_SWAP_MB)MB
	@echo "==> Checking swap space..."
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "ERROR: Must be root to configure swap"; \
		exit 1; \
	fi
	@CURRENT_SWAP_KB=$$(free | awk '/^Swap:/ {print $$2}'); \
	CURRENT_SWAP_MB=$$((CURRENT_SWAP_KB / 1024)); \
	echo "  Current swap: $${CURRENT_SWAP_MB}MB"; \
	if [ "$$CURRENT_SWAP_MB" -ge $(MIN_SWAP_MB) ]; then \
		echo "  [OK] Swap is already >= $(MIN_SWAP_MB)MB, nothing to do."; \
	else \
		echo "  [INFO] Swap is below $(MIN_SWAP_MB)MB, creating /swapfile..."; \
		if [ -f /swapfile ]; then \
			echo "  [INFO] /swapfile already exists, resizing..."; \
			swapoff /swapfile 2>/dev/null || true; \
		fi; \
		dd if=/dev/zero of=/swapfile bs=1M count=$(MIN_SWAP_MB) status=progress; \
		chmod 600 /swapfile; \
		mkswap /swapfile; \
		swapon /swapfile; \
		if ! grep -q '/swapfile' /etc/fstab; then \
			echo '/swapfile none swap sw 0 0' >> /etc/fstab; \
			echo "  [OK] Added /swapfile to /etc/fstab"; \
		fi; \
		echo "  [OK] Swap configured: $$(free -h | awk '/^Swap:/ {print $$2}')"; \
	fi

network: ## Create volume directories
	@echo "==> Setting up directories..."
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "ERROR: Must be root"; \
		exit 1; \
	fi
	@mkdir -p $(INSTALL_DIR)/traefik/certificates
	@echo "  [OK] Created $(INSTALL_DIR)/traefik/certificates"

install: check swap network ## Full installation (run with sudo)
	@echo ""
	@echo "==> Installing redlib to $(INSTALL_DIR)..."
	@# Copy docker-compose.yml
	@cp docker-compose.yml $(INSTALL_DIR)/docker-compose.yml
	@echo "  [OK] Copied docker-compose.yml to $(INSTALL_DIR)/"
	@# Create .env with CF_DNS_API_TOKEN if it doesn't exist
	@if [ -f $(INSTALL_DIR)/.env ]; then \
		echo "  [SKIP] $(INSTALL_DIR)/.env already exists, keeping current values"; \
	else \
		read -rp "  Enter your domain (REDLIB_DOMAIN, e.g. redlib.example.com): " redlib_domain; \
		read -rp "  Enter your Cloudflare DNS API token (CF_DNS_API_TOKEN): " cf_token; \
		read -rp "  Enter your ACME/Let's Encrypt email (ACME_EMAIL): " acme_email; \
		if [ -z "$$redlib_domain" ] || [ -z "$$cf_token" ] || [ -z "$$acme_email" ]; then \
			echo "  [WARN] Missing values — you must create $(INSTALL_DIR)/.env manually"; \
			echo "         Required: REDLIB_DOMAIN=... CF_DNS_API_TOKEN=... ACME_EMAIL=..."; \
		else \
			printf 'REDLIB_DOMAIN=%s\nCF_DNS_API_TOKEN=%s\nACME_EMAIL=%s\n' "$$redlib_domain" "$$cf_token" "$$acme_email" > $(INSTALL_DIR)/.env; \
			chmod 600 $(INSTALL_DIR)/.env; \
			echo "  [OK] Created $(INSTALL_DIR)/.env"; \
		fi; \
	fi
	@# Install watchdog script
	@cp docker-watchdog.sh $(WATCHDOG_BIN)
	@chmod +x $(WATCHDOG_BIN)
	@echo "  [OK] Installed watchdog script to $(WATCHDOG_BIN)"
	@# Install systemd service
	@cp docker-watchdog.service $(SERVICE_FILE)
	@echo "  [OK] Installed systemd service to $(SERVICE_FILE)"
	@# Enable and start
	@systemctl daemon-reload
	@systemctl enable --now docker-watchdog.service
	@echo "  [OK] Watchdog service enabled and started"
	@# Start the stack
	@cd $(INSTALL_DIR) && docker compose up -d
	@echo ""
	@echo "============================================"
	@echo "  Redlib installation complete!"
	@echo "  Install dir : $(INSTALL_DIR)"
	@echo "  Watchdog     : systemctl status docker-watchdog"
	@echo "  Containers   : cd $(INSTALL_DIR) && docker compose ps"
	@echo "============================================"

uninstall: ## Remove redlib installation (run with sudo)
	@echo "==> Uninstalling redlib..."
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "ERROR: Must be root"; \
		exit 1; \
	fi
	@# Stop watchdog service
	@if systemctl is-active --quiet docker-watchdog.service 2>/dev/null; then \
		systemctl stop docker-watchdog.service; \
		echo "  [OK] Stopped watchdog service"; \
	fi
	@if systemctl is-enabled --quiet docker-watchdog.service 2>/dev/null; then \
		systemctl disable docker-watchdog.service; \
		echo "  [OK] Disabled watchdog service"; \
	fi
	@# Stop docker compose stack
	@if [ -f $(INSTALL_DIR)/docker-compose.yml ]; then \
		cd $(INSTALL_DIR) && docker compose down; \
		echo "  [OK] Stopped docker compose stack"; \
	fi
	@# Remove installed files
	@rm -f $(WATCHDOG_BIN)
	@echo "  [OK] Removed $(WATCHDOG_BIN)"
	@rm -f $(SERVICE_FILE)
	@systemctl daemon-reload
	@echo "  [OK] Removed $(SERVICE_FILE)"
	@# Prompt before removing install dir
	@if [ -d $(INSTALL_DIR) ]; then \
		read -rp "  Remove $(INSTALL_DIR) and all data? [y/N] " confirm; \
		if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
			rm -rf $(INSTALL_DIR); \
			echo "  [OK] Removed $(INSTALL_DIR)"; \
		else \
			echo "  [SKIP] Kept $(INSTALL_DIR)"; \
		fi; \
	fi
	@echo "==> Uninstall complete."
	@echo "  NOTE: Docker network 'traefik' and swap were preserved."

status: ## Show current status of all components
	@echo "==> Redlib Status"
	@echo ""
	@echo "--- Watchdog Service ---"
	@systemctl status docker-watchdog.service --no-pager 2>/dev/null || echo "  Service not installed"
	@echo ""
	@echo "--- Docker Containers ---"
	@if [ -f $(INSTALL_DIR)/docker-compose.yml ]; then \
		cd $(INSTALL_DIR) && docker compose ps; \
	else \
		echo "  docker-compose.yml not found at $(INSTALL_DIR)"; \
	fi
	@echo ""
	@echo "--- Swap ---"
	@free -h | grep -E '^(Mem|Swap):'
	@echo ""
	@echo "--- Docker Network 'traefik' ---"
	@docker network inspect traefik --format '{{.Name}} ({{.Driver}}, {{.Scope}})' 2>/dev/null || echo "  Network 'traefik' does not exist"
