# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please report it responsibly.

Please [open a GitHub issue](https://github.com/axeII/selfhost-redlib/issues/new) with:

- A description of the vulnerability
- Steps to reproduce
- Potential impact
- Any suggested fixes (optional)

## Scope

This policy covers the deployment configuration in this repository:

- `docker-compose.yml` (container configuration, network exposure, volume mounts)
- `Makefile` (installer logic, file permissions, system modifications)
- `docker-watchdog.sh` (watchdog script)
- `docker-watchdog.service` (systemd unit)

Vulnerabilities in upstream projects (Redlib, Traefik, Watchtower, Docker) should be reported to their respective maintainers.

## Supported Versions

Only the latest version on the `main` branch is supported with security updates.
