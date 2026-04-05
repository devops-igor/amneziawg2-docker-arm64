# =============================================================================
# Stage 1: Builder — compile amneziawg-go and amneziawg-tools from source
# =============================================================================
FROM --platform=$BUILDPLATFORM golang:alpine AS builder

# Build arguments for cross-compilation
ARG TARGETOS
ARG TARGETARCH
ARG BUILDARCH
ARG GOARM

# Install build dependencies
RUN apk add --no-cache \
    gcc \
    musl-dev \
    make \
    bash \
    git \
    ca-certificates \
    iproute2 \
    autoconf \
    automake \
    libtool \
    pkgconfig \
    linux-headers \
    libmnl-dev \
    libretls-dev \
    openssl-dev \
    musl-obstack

ENV GOARCH=${TARGETARCH} \
    CGO_ENABLED=1 \
    GO111MODULE=on

WORKDIR /build

# Clone and build amneziawg-go
RUN git clone --depth 1 --branch v0.2.16 https://github.com/amnezia-vpn/amneziawg-go.git

WORKDIR /build/amneziawg-go
RUN go build -ldflags="-s -w" -o amneziawg-go .

# Clone and build amneziawg-tools
WORKDIR /build
RUN git clone --depth 1 --branch v1.0.20260223 https://github.com/amnezia-vpn/amneziawg-tools.git

WORKDIR /build/amneziawg-tools/src
RUN ./configure \
    --prefix=/usr \
    --sysconfdir=/etc \
    --with-systemd=no \
    --with-awg \
    --with-kernel-headers=/usr/include \
    && make -j$(nproc) \
    && make install DESTDIR=/out

# Copy binaries to out directory
WORKDIR /out
RUN mkdir -p /out/bin && \
    cp /build/amneziawg-go/amneziawg-go /out/bin/ && \
    cp /build/amneziawg-tools/src/awg /out/bin/ && \
    cp /build/amneziawg-tools/src/awg-quick /out/bin/ 2>/dev/null || \
    cp $(find /build/amneziawg-tools -name 'awg*' -type f) /out/bin/ 2>/dev/null || true

# List what's in /out for debugging
RUN ls -laR /out

# =============================================================================
# Stage 2: Runtime — minimal Alpine image with binaries
# =============================================================================
FROM alpine:latest AS runtime

# Install runtime dependencies
RUN apk add --no-cache \
    bash \
    iproute2 \
    ca-certificates \
    libretls \
    libmnl \
    musl

# Create non-root user for better security
RUN addgroup -g 1000 amneziawg && \
    adduser -u 1000 -G amneziawg -s /bin/bash -D amneziawg

# Create config directory (volume mount point)
RUN mkdir -p /config && chown amneziawg:amneziawg /config

# Copy binaries from builder stage
COPY --from=builder /out/bin/ /usr/local/bin/

# Set executable permissions
RUN chmod +x /usr/local/bin/amneziawg-go /usr/local/bin/awg /usr/local/bin/awg-quick 2>/dev/null || \
    chmod +x /usr/local/bin/*

# Drop privileges
USER amneziawg

# Copy entrypoint script
COPY scripts/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD awg show >/dev/null 2>&1 || exit 1

WORKDIR /config
ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]
