# amneziawg-client-docker

> **AmneziaWG 2.0 Docker Client** — Userspace VPN client for `linux/arm64`

A minimal Docker image that runs [AmneziaWG 2.0](https://github.com/amnezia-vpn/amneziawg-go) client using the userspace `amneziawg-go` implementation. No kernel module required — works on Raspberry Pi, ARM servers, NAS devices, and anywhere Docker runs.

## Why Userspace?

The AmneziaWG kernel module requires compiling against host kernel headers — impractical in a container. `amneziawg-go` runs fully in userspace and works everywhere Docker runs. Full AmneziaWG 2.0 obfuscation support is preserved.

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

## Prerequisites

- **Docker** 20.10+ with `docker buildx` for multi-arch builds
- **TUN device** — must be available inside the container (`--device /dev/net/tun:/dev/net/tun`)
- **Linux host** — kernel support for TUN/TAP (`CONFIG_TUN=m`)
- **Capabilities:** `NET_ADMIN` is required to create the network interface

### Check TUN availability on host

```bash
ls -la /dev/net/tun
# Should show: crw-rw---- 1 root root 10, 200 ... /dev/net/tun
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

## AmneziaWG 2.0 Obfuscation Parameters

AmneziaWG 2.0 adds powerful DPI-evasion features. Your config file **must** include matching values from your server admin:

### Junk Packets

```
Jc = 4         # Number of junk packets per handshake
Jmin = 50      # Min junk packet size (bytes)
Jmax = 1000    # Max junk packet size (bytes)
```

### Packet Padding

```
S1 = 86        # Init byte count
S2 = 12        # Response byte count
S3 = 25        # Padding divisor
S4 = 15        # Padding multiplier
```

### Dynamic Headers

```
H1 = 1755269708    # Header value 1
H2 = 2101520157    # Header value 2
H3 = 1829552136    # Header value 3
H4 = 2016351429    # Header value 4
# Can also be ranges: H1 = 100-200
```

### CPS Signature Packets

```
I1 = <b 0xc0000000><r 16><t>   # IPv4 signature pattern
I2 =                              # Leave empty or specify
I3 =
I4 =
I5 =
```

> **Important:** All obfuscation params MUST match your server exactly. Contact your server admin for the correct values.

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

> **Security note:** Keep your `.conf` file backed up and never commit it to version control.

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

### Obfuscation params not working

- Verify your config has all required `Jc`, `S1-S4`, `H1-H4`, `I1-I5` values
- They MUST match your server config exactly
- If values are missing in your config, the server may be using defaults — check with your server admin

---

## Architecture

- **Build stage:** `golang:alpine` — compiles `amneziawg-go` and `amneziawg-tools` from source
- **Runtime stage:** `alpine:3.20` — minimal image with only runtime deps
- **Binaries:** `amneziawg-go` (userspace WireGuard), `awg` (CLI tool), `awg-quick` (interface manager)

---

## Security Notes

- No hardcoded secrets or keys in any file
- Config file should be mounted read-only (`:ro`)
- Container starts as root (required for networking) and drops to non-root user `amneziawg:1000` for the long-running process
- The `amneziawg` user has passwordless sudo restricted to networking commands (`ip`, `iptables`, `awg`, `awg-quick`) — this is defense-in-depth, not a true sandbox, since the container already holds `NET_ADMIN`
- Review Docker's capability requirements before running in production

---

## License

MIT — See repository for details.
