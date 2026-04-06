# AmneziaWG 2.0 Docker Client

[![Docker Pulls](https://img.shields.io/docker/pulls/devopsigor/awg2-arm64)](https://hub.docker.com/r/devopsigor/awg2-arm64)
[![License](https://img.shields.io/github/license/devops-igor/amneziawg2-docker-arm64)](LICENSE)
[![Docker Image Size](https://img.shields.io/docker/image-size/devopsigor/awg2-arm64/latest)](https://hub.docker.com/r/devopsigor/awg2-arm64)
[![Platform](https://img.shields.io/badge/platform-linux%2Farm64-blue)]()

> Lightweight Docker image for running AmneziaWG 2.0 VPN on ARM64 devices

---

## Table of Contents

- [Quick Start](#quick-start)
- [Volume Mount](#volume-mount)
- [Required Capabilities & Sysctls](#required-capabilities--sysctls)
- [Healthcheck](#healthcheck)
- [Example Config File](#example-config-file)
- [Docker Compose](#docker-compose)
- [Build from Source](#build-from-source)
- [Security Notes](#security-notes)
- [Troubleshooting](#troubleshooting)
- [License](#license)

---

A minimal Docker image that runs [AmneziaWG 2.0](https://github.com/amnezia-vpn/amneziawg-go) client using the userspace `amneziawg-go` implementation. No kernel module required - works on Raspberry Pi, ARM servers, NAS devices, and anywhere Docker runs.

---

## Quick Start

```bash
# Run
docker run \
  --name amneziawg-client \
  --cap-add NET_ADMIN \
  --device /dev/net/tun:/dev/net/tun \
  --sysctl net.ipv4.ip_forward=1 \
  --sysctl net.ipv4.conf.all.src_valid_mark=1 \
  -v /path/to/your/amneziawg.conf:/config/amneziawg.conf:ro \
  devopsigor/awg2-arm64:latest
```

---

## Volume Mount

The config file **must** be mounted read-only at `/config/amneziawg.conf`:

```bash
-v /path/to/config:/config/amneziawg.conf:ro
```

The entrypoint validates:
- File exists
- Contains `[Interface]` section
- Contains at least one `[Peer]` section

---

## Required Capabilities & Sysctls

```bash
docker run \
  --cap-add NET_ADMIN          # Required to create TUN interface
  --device /dev/net/tun:/dev/net/tun  # TUN device access
  --sysctl net.ipv4.ip_forward=1   # Enable packet forwarding
  --sysctl net.ipv4.conf.all.src_valid_mark=1  # Required for WireGuard/AmneziaWG
  ...
```

> **Note:** On some systems (Synology NAS, OpenWrt), you may also need `--privileged`. Try that if you get permission errors.

---

## Healthcheck

The container has a built-in healthcheck:

```bash
# Check status
docker inspect --format='{{.State.Health.Status}}' amneziawg-client

# Verify interface is up inside container
docker exec amneziawg-client awg show
```

Healthcheck runs `awg show` every 30s. If it fails 3 times, the container is marked **unhealthy**.

---

## Example Config File

See [`config/amneziawg.conf.example`](config/amneziawg.conf.example) for a fully documented example.

---

## Docker Compose

```yaml
version: "3.8"

services:
  amneziawg:
    # image: ghcr.io/igorkon/amneziawg-client:latest  # uncomment when published
    container_name: amneziawg-client
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
    volumes:
      - /path/to/amneziawg.conf:/config/amneziawg.conf:ro
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "awg", "show"]
      interval: 30s
      timeout: 10s
      retries: 3
```

---

## Build from Source

### Prerequisites

- Docker 20.10+
- `docker buildx` with `linux/arm64` platform support

### Build

```bash
# Clone the repo
git clone https://github.com/devops-igor/amneziawg2-docker-arm64.git
cd amneziawg2-docker-arm64

# Build for your current architecture
docker build -t amneziawg-client:local .

# Or build for arm64 explicitly
docker buildx build --platform linux/arm64 -t amneziawg-client:local .

# Override version pins (defaults: v0.2.16, v1.0.20260223)
docker buildx build --platform linux/arm64 \
  --build-arg AWG_GO_VERSION=v0.2.16 \
  --build-arg AWG_TOOLS_VERSION=v1.0.20260223 \
  -t amneziawg-client:local .
```

### Build Command That Worked

```
docker buildx build --platform linux/arm64 -t amneziawg-client:local .
```

### Verify Build

```bash
# Check image size (should be <100MB)
docker images amneziawg-client:local

# Test it starts (with a valid config)
docker run --rm \
  --cap-add NET_ADMIN \
  --device /dev/net/tun:/dev/net/tun \
  --sysctl net.ipv4.ip_forward=1 \
  --sysctl net.ipv4.conf.all.src_valid_mark=1 \
  -v /path/to/test.conf:/config/amneziawg.conf:ro \
  amneziawg-client:local

# Check healthcheck
docker inspect --format='{{.State.Health.Status}}' <container_id>
```

Expected image size: **< 100MB** (target: < 50MB, optimized for a minimal footprint)

---

## Troubleshooting

### "Device or resource busy" when accessing `/dev/net/tun`

The TUN device is already in use or not available. Try:
```bash
# Check if tun module is loaded
lsmod | grep tun

# Load it manually
sudo modprobe tun
```

### "RTNETLINK: Operation not permitted"

Missing `NET_ADMIN` capability or running in an unprivileged environment (some NAS, WSL2):
```bash
# Try privileged mode (less secure)
docker run --privileged ...
```

### Healthcheck shows "unhealthy" immediately

1. Verify your config file is valid
2. Check logs: `docker logs <container>`
3. Run interactively to see errors:
   ```bash
   docker run --rm -it \
     --cap-add NET_ADMIN \
     --device /dev/net/tun:/dev/net/tun \
     --sysctl net.ipv4.ip_forward=1 \
     --sysctl net.ipv4.conf.all.src_valid_mark=1 \
     -v /path/to/config:/config/amneziawg.conf:ro \
     amneziawg-client:local /bin/sh
   ```

### Container exits immediately with code 0

The config may be invalid or the tunnel failed to start. Check logs:
```bash
docker logs <container>
```

---

## Security Notes

- No hardcoded secrets or keys in any file
- Config file should be mounted read-only (`:ro`)
- Container starts as root (required for networking) and drops to non-root user `amneziawg:1000` for the long-running process
- The `amneziawg` user has passwordless sudo restricted to networking commands (`ip`, `iptables`, `awg`, `awg-quick`) - this is defense-in-depth, not a true sandbox, since the container already holds `NET_ADMIN`
- Review Docker's capability requirements before running in production

---

## License

MIT - See repository for details.
