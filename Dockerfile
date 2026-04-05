# =============================================================================
# Stage 1: Builder — compile amneziawg-go and amneziawg-tools from source
# =============================================================================
FROM --platform=$BUILDPLATFORM golang:alpine AS builder

# Build arguments for cross-compilation
ARG TARGETOS
ARG TARGETARCH
ARG BUILDARCH
ARG GOARM

# Version pinning — override at build time without editing Dockerfile
ARG AWG_GO_VERSION=v0.2.16
ARG AWG_TOOLS_VERSION=v1.0.20260223

# Install build dependencies
RUN apk add --no-cache \
    gcc \
    musl-dev \
    make \
    bash \
    git \
    linux-headers \
    libmnl-dev \
    openssl-dev

ENV GOARCH=${TARGETARCH} \
    CGO_ENABLED=1 \
    GO111MODULE=on

WORKDIR /build

# Clone and build amneziawg-go
RUN git clone --depth 1 --branch ${AWG_GO_VERSION} https://github.com/amnezia-vpn/amneziawg-go.git

WORKDIR /build/amneziawg-go
RUN go build -ldflags="-s -w" -o amneziawg-go .

# Clone and build amneziawg-tools (plain Makefile, no configure script)
WORKDIR /build
RUN git clone --depth 1 --branch ${AWG_TOOLS_VERSION} https://github.com/amnezia-vpn/amneziawg-tools.git

WORKDIR /build/amneziawg-tools/src
RUN make -j$(nproc) && \
    make install DESTDIR=/out PREFIX=/usr WITH_WGQUICK=yes

# Copy binaries to out directory
WORKDIR /out
RUN mkdir -p /out/bin && \
    cp /build/amneziawg-go/amneziawg-go /out/bin/ && \
    cp /out/usr/bin/awg /out/bin/ && \
    cp /out/usr/bin/awg-quick /out/bin/

# =============================================================================
# Stage 2: Runtime — minimal Alpine image with binaries
# =============================================================================
FROM alpine:3.20 AS runtime

# Install runtime dependencies
RUN apk add --no-cache \
    bash \
    iproute2 \
    iptables \
    sudo \
    ca-certificates \
    libretls \
    libmnl \
    musl

# Create non-root user with restricted sudo for networking commands only
# (awg-quick needs ip, iptables, and resolvconf to manage the tunnel)
RUN addgroup -g 1000 amneziawg && \
    adduser -u 1000 -G amneziawg -s /bin/bash -D amneziawg && \
    echo 'Defaults:amneziawg !requiretty' >> /etc/sudoers && \
    echo 'amneziawg ALL=(root) NOPASSWD: /sbin/ip, /usr/sbin/iptables, /sbin/iptables, /usr/local/bin/awg, /usr/local/bin/awg-quick, /usr/bin/resolvconf' >> /etc/sudoers

# Create config directory (volume mount point)
RUN mkdir -p /config && chown amneziawg:amneziawg /config

# Copy binaries from builder stage
COPY --from=builder /out/bin/ /usr/local/bin/

# Set executable permissions
RUN chmod +x /usr/local/bin/amneziawg-go /usr/local/bin/awg /usr/local/bin/awg-quick 2>/dev/null || \
    chmod +x /usr/local/bin/*

# Symlink wg → awg (awg-quick calls 'wg' internally)
RUN ln -sf /usr/local/bin/awg /usr/local/bin/wg

# Stub resolvconf so awg-quick doesn't fail (we handle DNS in entrypoint)
RUN printf '#!/bin/sh\nexit 0\n' > /usr/local/bin/resolvconf && \
    chmod +x /usr/local/bin/resolvconf

# Copy entrypoint script
COPY scripts/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD awg show >/dev/null 2>&1 || exit 1

WORKDIR /config
ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
