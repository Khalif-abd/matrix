# Matrix Installer

One-command installer for a self-hosted Matrix Synapse + Element + Coturn + Caddy stack.

## Quick Start

```bash
bash <(curl -Ls https://raw.githubusercontent.com/khalif-abd/matrix/main/install.sh)
```

Or download and run:

```bash
curl -LO https://raw.githubusercontent.com/YOUR_USER/matrix-installer/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

## What it installs

| Component | Purpose |
|-----------|---------|
| **Synapse** | Matrix homeserver |
| **PostgreSQL 16** | Database |
| **Element Web** | Web client |
| **Coturn** | TURN/STUN server for voice/video calls |
| **Caddy** | Reverse proxy + auto SSL |
| **Synapse Admin** | Web admin panel (optional) |

## Requirements

- Ubuntu 22.04 / 24.04 or Debian 12+
- Root access
- 4 GB RAM / 2 vCPU / 50 GB SSD (recommended for ~50 users)
- Domain with 3 A records pointing to the server

## DNS Setup (before running)

| Type | Name | Value |
|------|------|-------|
| A | `matrix.example.com` | `SERVER_IP` |
| A | `element.example.com` | `SERVER_IP` |
| A | `turn.example.com` | `SERVER_IP` |
| A | `admin.example.com` | `SERVER_IP` (optional) |

## Features

- Interactive setup wizard
- Auto-generated passwords and secrets
- Auto SSL via Caddy (Let's Encrypt)
- PostgreSQL instead of SQLite
- TURN server for reliable voice/video calls
- E2E encryption enabled by default
- Dark theme Element Web
- `.well-known` delegation support
- Optional web admin panel (user management, rooms, media)
- Optional auto-purge: messages (configurable retention) and media (cron-based)
- Built-in uninstall script for clean removal

## After Install

### Add new user

```bash
cd /opt/matrix
docker compose exec synapse register_new_matrix_user http://localhost:8008 -c /data/homeserver.yaml
```

### Update

```bash
cd /opt/matrix
docker compose pull && docker compose up -d
```

### Backup

```bash
cd /opt/matrix
docker compose exec postgres pg_dump -U synapse synapse > backup_$(date +%Y%m%d).sql
```

### Logs

```bash
cd /opt/matrix && docker compose logs -f
```

### Manual media purge

```bash
sudo bash install.sh --purge-media
# or directly:
/opt/matrix/purge-media.sh
```

### Full uninstall (removes EVERYTHING)

```bash
sudo bash install.sh --uninstall
# or directly:
/opt/matrix/uninstall.sh
```

### CLI flags

```
sudo bash install.sh              # Interactive install
sudo bash install.sh --uninstall   # Full removal
sudo bash install.sh --purge-media # Manual media purge
sudo bash install.sh --help        # Help
```

## Clients

| Platform | App |
|----------|-----|
| Android | [Element](https://play.google.com/store/apps/details?id=im.vector.app) |
| iOS | [Element](https://apps.apple.com/app/element-messenger/id1083446067) |
| macOS | `brew install --cask element` |
| Windows | [element.io/download](https://element.io/download) |
| Linux | Flatpak / Snap / AppImage |

## License

MIT