# selfhost-redlib

A one-command self-hosted [Redlib](https://github.com/redlib-org/redlib) setup with Traefik reverse proxy, automatic HTTPS via Cloudflare DNS, Watchtower for auto-updates, and a watchdog service for health monitoring.

## What's Included

| Component | Purpose |
|---|---|
| **Redlib** | Private, ad-free Reddit frontend (Rust) |
| **Traefik** | Reverse proxy with automatic Let's Encrypt TLS via Cloudflare DNS |
| **Watchtower** | Automatic container image updates |
| **Watchdog** | systemd service that monitors Redlib and force-recreates containers on failure |

## Prerequisites

- Linux server (Debian/Ubuntu recommended)
- [Docker](https://docs.docker.com/engine/install/) with the [Compose plugin](https://docs.docker.com/compose/install/)
- `curl` (used by the watchdog script)
- A domain pointed to your server (managed via Cloudflare DNS)
- A [Cloudflare API token](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/) with `Zone:DNS:Edit` permission

## Quick Start

```bash
git clone https://github.com/axeII/selfhost-redlib.git
cd selfhost-redlib
sudo make install
```

The installer will:

1. Verify Docker, Docker Compose, and curl are installed
2. Ensure at least 2 GB of swap space (creates `/swapfile` if needed)
3. Create the install directory and certificate volume at `/opt/redlib`
4. Prompt for your Cloudflare DNS API token and write `/opt/redlib/.env`
5. Install the watchdog script and systemd service
6. Start all containers

## Configuration

During `make install`, you will be prompted for:

- **REDLIB_DOMAIN** — your domain (e.g. `redlib.example.com`)
- **CF_DNS_API_TOKEN** — your Cloudflare API token with `Zone:DNS:Edit` permission
- **ACME_EMAIL** — email for Let's Encrypt certificate registration

All values are stored in `/opt/redlib/.env` (permissions `600`).

## Makefile Targets

```
sudo make install     # Full installation
sudo make uninstall   # Remove everything (prompts before deleting data)
sudo make check       # Verify prerequisites only
sudo make swap        # Configure swap space only
sudo make status      # Show service, container, swap, and network status
make help             # List all targets
```

## Architecture

```
Internet
  │
  ▼
┌──────────┐    ┌──────────┐
│  Traefik │───▶│  Redlib  │
│ :80/:443 │    │  :8080   │
└──────────┘    └──────────┘
       │
  TLS termination
  (Let's Encrypt via
   Cloudflare DNS)

┌────────────┐   ┌──────────┐
│ Watchtower │   │ Watchdog │
│ (auto-pull)│   │(systemd) │
└────────────┘   └──────────┘
```

- **Traefik** handles TLS termination and routes HTTPS traffic to Redlib
- **Redlib** listens only on `127.0.0.1:8081` — not directly exposed to the internet
- **Watchtower** polls for new container images every hour
- **Watchdog** checks `http://localhost:8081/settings` every 10 minutes and force-recreates containers if it returns 404

## Security Hardening

The Docker Compose setup includes several security measures:

- Redlib runs as `nobody` with `read_only: true` filesystem
- All containers drop all Linux capabilities (`cap_drop: ALL`)
- Privilege escalation is blocked (`no-new-privileges`)
- Traefik dashboard is bound to localhost only
- Redlib port is bound to localhost only (Traefik proxies public traffic)
- Docker socket is mounted read-only where possible
- Resource limits prevent runaway memory/CPU usage
- Search engine indexing is disabled
- Log rotation is configured on all containers
- The `.env` file containing the API token is created with `600` permissions

## File Overview

```
.
├── docker-compose.yml      # Full stack: Traefik + Redlib + Watchtower
├── docker-watchdog.sh       # Watchdog bash script (installed to /usr/local/bin/)
├── docker-watchdog.service  # systemd unit for the watchdog
├── Makefile                 # Installer
├── LICENSE
├── SECURITY.md
└── README.md
```

## Logs

- **Watchdog**: `/var/log/docker-watchdog.log`
- **Container logs**: `docker compose -f /opt/redlib/docker-compose.yml logs -f`
- **Watchdog service**: `journalctl -u docker-watchdog.service -f`

## Uninstalling

```bash
sudo make uninstall
```

This stops all services and containers, removes the watchdog script and systemd service, and optionally deletes `/opt/redlib`. Swap configuration is preserved.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

## Security

To report a security vulnerability, please see [SECURITY.md](SECURITY.md).
