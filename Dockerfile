# Multi-Stage Dockerfile for Akkoma OTP Release
# Downloads pre-built OTP release and creates a minimal runtime image
#
# Build arguments:
#   AKKOMA_VERSION: Release version to download (stable, develop, or version tag) - default: stable
#     CI always passes the chart's appVersion (vX.Y.Z); for those the build
#     also checks the downloaded release reports that version.
#   AKKOMA_PINNED_*: see the downloader stage -- for a release upstream only
#     published under a floating path, pinned by SHA-256.
#
# Build command:
#   docker build -t akkoma:latest .
#   docker build -t akkoma:stable --build-arg AKKOMA_VERSION=stable .
#
# Multi-arch build:
#   docker buildx build --platform linux/amd64,linux/arm64 -t akkoma:latest .
#
# Expected characteristics:
#   - Build time: 1-2 minutes (download only)
#   - Image size: ~374MB uncompressed (~91MB compressed)
#   - Architecture: amd64, arm64

# ============================================================================
# Stage 1: Downloader - Download pre-built OTP release
# ============================================================================
# Base image pinned by digest (both stages), so the image only changes when
# this line changes: Renovate opens a PR when alpine:3.24 is rebuilt (e.g.
# for security fixes). A digest bump rebuilds the image under the same Akkoma
# version -- see "Base image updates" in CLAUDE.md for releasing it.
FROM alpine:3.24@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6 AS downloader

# Install download dependencies
RUN apk add --no-cache \
    curl \
    unzip

# Set build-time arguments
ARG AKKOMA_VERSION=stable
ARG TARGETARCH

# Release archives normally live at <AKKOMA_VERSION>/. When upstream publishes
# a release only under a floating path (e.g. stable/), pin it here: building
# AKKOMA_PINNED_VERSION downloads from AKKOMA_PINNED_PATH and fails unless the
# archive matches the recorded SHA-256, so the build stays immutable -- if
# upstream replaces the archive, the build breaks instead of silently changing.
#
# v3.20.1 (2026.09 security release): tagged at 98dd958, but its build was
# only published as stable/ -- built from bc62dd8, the tag plus a CI-only
# follow-up merge ("use later base images to build releases"). The archives
# report 3.20.1-0-gbc62dd8. Drop this once appVersion moves past v3.20.1.
ARG AKKOMA_PINNED_VERSION=v3.20.1
ARG AKKOMA_PINNED_PATH=stable
ARG AKKOMA_PINNED_SHA256_AMD64=02c1db1b0a32d2f7ca4806967461f19387da0ba5186f925bc3156798aa1cc0e2
ARG AKKOMA_PINNED_SHA256_ARM64=c66694a28b73eafcb16281c46d06ba18837055892a648a86d28a41db131fcf87

WORKDIR /tmp

# Select the correct flavour based on target architecture
# amd64 -> amd64-musl, arm64 -> arm64-musl
RUN set -e; \
    AKKOMA_FLAVOUR="${TARGETARCH}-musl"; \
    path="${AKKOMA_VERSION}"; sha=""; \
    if [ "${AKKOMA_VERSION}" = "${AKKOMA_PINNED_VERSION}" ]; then \
        path="${AKKOMA_PINNED_PATH}"; \
        case "${TARGETARCH}" in \
            amd64) sha="${AKKOMA_PINNED_SHA256_AMD64}" ;; \
            arm64) sha="${AKKOMA_PINNED_SHA256_ARM64}" ;; \
            *) echo "ERROR: no pinned checksum for ${TARGETARCH}"; exit 1 ;; \
        esac; \
    fi; \
    echo "Downloading Akkoma ${AKKOMA_VERSION} (${AKKOMA_FLAVOUR}) from ${path}/..."; \
    curl -f -L --retry 3 --retry-delay 5 --max-time 300 \
        "https://akkoma-updates.s3-website.fr-par.scw.cloud/${path}/akkoma-${AKKOMA_FLAVOUR}.zip" \
        -o akkoma.zip; \
    if [ -n "${sha}" ]; then \
        echo "${sha}  akkoma.zip" | sha256sum -c - \
            || { echo "ERROR: ${path}/akkoma-${AKKOMA_FLAVOUR}.zip no longer matches the pinned SHA-256 for ${AKKOMA_VERSION}"; exit 1; }; \
    fi; \
    unzip -q akkoma.zip || { echo "ERROR: Failed to extract release archive"; exit 1; }; \
    rm akkoma.zip; \
    case "${AKKOMA_VERSION}" in \
        v[0-9]*) \
            want="${AKKOMA_VERSION#v}"; \
            got="$(cut -d' ' -f2 release/releases/start_erl.data)"; \
            case "${got}" in \
                "${want}"|"${want}"-*|"${want}"+*) echo "Release reports ${got}" ;; \
                *) echo "ERROR: archive reports Akkoma ${got}, expected ${want}"; exit 1 ;; \
            esac ;; \
    esac

# Verify the release structure and binary executability
RUN test -d /tmp/release || \
        (echo "ERROR: Release directory not found" && \
         echo "Contents of /tmp:" && \
         ls -la /tmp && \
         exit 1) && \
    test -f /tmp/release/bin/pleroma || \
        (echo "ERROR: pleroma binary not found at /tmp/release/bin/pleroma" && \
         echo "Contents of /tmp/release:" && \
         ls -la /tmp/release && \
         exit 1) && \
    test -x /tmp/release/bin/pleroma || \
        (echo "ERROR: pleroma binary is not executable" && \
         ls -l /tmp/release/bin/pleroma && \
         exit 1)

# ============================================================================
# Stage 2: Runtime - Minimal Alpine-based image
# ============================================================================
FROM alpine:3.24@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6

# Install runtime dependencies
# Based on: https://docs.akkoma.dev/stable/installation/otp_en/
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

# Create akkoma user and group (UID/GID 10001, outside the 0-10000 range
# some hardening scanners flag as reserved/host-collision-prone)
# Running as non-root user for security
RUN addgroup -g 10001 akkoma && \
    adduser -D -u 10001 -G akkoma akkoma

# Copy OTP release from downloader stage
COPY --from=downloader --chown=akkoma:akkoma \
    /tmp/release /opt/akkoma

# Set working directory
WORKDIR /opt/akkoma

# Switch to non-root user
USER akkoma

# Expose application port
EXPOSE 4000

# Start Akkoma application
# Note: Kubernetes will manage health probes - no HEALTHCHECK directive
CMD ["./bin/pleroma", "start"]
