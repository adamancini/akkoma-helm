# Multi-Stage Dockerfile for Akkoma OTP Release
# Builds Akkoma from source and creates a minimal runtime image
#
# Build arguments:
#   AKKOMA_VERSION: Git ref to build (tag, branch, commit) - default: v3.13.2
#
# Build command:
#   docker build -t akkoma:latest .
#   docker build -t akkoma:v3.13.2 --build-arg AKKOMA_VERSION=v3.13.2 .
#
# Expected characteristics:
#   - Build time: 10-15 minutes
#   - Image size: ~200MB
#   - Architecture: amd64

# ============================================================================
# Stage 1: Builder - Build OTP release from source
# ============================================================================
FROM elixir:1.14-alpine AS builder

# Install build dependencies
RUN apk add --no-cache \
    git \
    build-base \
    cmake \
    postgresql-client

# Set build-time argument for Akkoma version
ARG AKKOMA_VERSION=v3.13.2

WORKDIR /build

# Clone Akkoma source code at specified version
RUN git clone --branch ${AKKOMA_VERSION} \
    https://akkoma.dev/AkkomaGang/akkoma.git . && \
    mix local.hex --force && \
    mix local.rebar --force

# Set production environment for Mix
ENV MIX_ENV=prod

# Get dependencies and build OTP release
RUN mix deps.get --only prod && \
    mix do compile, release

# ============================================================================
# Stage 2: Runtime - Minimal Alpine-based image
# ============================================================================
FROM alpine:3.19

# Install runtime dependencies
# - ncurses-libs: Required by Erlang/BEAM VM
# - postgresql-client: Database connectivity
# - imagemagick: Image processing
# - ffmpeg: Video processing
# - exiftool: Metadata extraction
# - libmagic, file: File type detection
# - ca-certificates, openssl: TLS/HTTPS support
RUN apk add --no-cache \
    ncurses-libs \
    postgresql-client \
    imagemagick \
    ffmpeg \
    exiftool \
    libmagic \
    file \
    ca-certificates \
    openssl

# Create akkoma user and group (UID/GID 1000)
# Running as non-root user for security
RUN addgroup -g 1000 akkoma && \
    adduser -D -u 1000 -G akkoma akkoma

# Copy OTP release from builder stage
# Ownership set to akkoma:akkoma for security
COPY --from=builder --chown=akkoma:akkoma \
    /build/_build/prod/rel/pleroma /opt/akkoma

# Set working directory
WORKDIR /opt/akkoma

# Switch to non-root user
USER akkoma

# Expose application port
EXPOSE 4000

# Start Akkoma application
# Note: Kubernetes will manage health probes - no HEALTHCHECK directive
CMD ["./bin/pleroma", "start"]
