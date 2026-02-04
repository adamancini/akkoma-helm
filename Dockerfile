# Multi-Stage Dockerfile for Akkoma OTP Release
# Downloads pre-built OTP release and creates a minimal runtime image
#
# Build arguments:
#   AKKOMA_VERSION: Release version to download (stable, develop, or version tag) - default: stable
#   AKKOMA_FLAVOUR: Platform flavour (amd64-musl for Alpine) - default: amd64-musl
#
# Build command:
#   docker build -t akkoma:latest .
#   docker build -t akkoma:stable --build-arg AKKOMA_VERSION=stable .
#
# Expected characteristics:
#   - Build time: 1-2 minutes (download only)
#   - Image size: ~374MB uncompressed (~91MB compressed)
#   - Architecture: amd64 (Alpine/musl)

# ============================================================================
# Stage 1: Downloader - Download pre-built OTP release
# ============================================================================
FROM alpine:3.19 AS downloader

# Install download dependencies
RUN apk add --no-cache \
    curl \
    unzip

# Set build-time arguments
ARG AKKOMA_VERSION=stable
ARG AKKOMA_FLAVOUR=amd64-musl

WORKDIR /tmp

# Download and extract pre-built OTP release
# Source: https://docs.akkoma.dev/stable/installation/otp_en/
# Security Note: No checksum verification is performed. Release is downloaded directly
# from Akkoma's official S3 bucket (akkoma-updates.s3-website.fr-par.scw.cloud)
RUN echo "Downloading Akkoma ${AKKOMA_VERSION} (${AKKOMA_FLAVOUR})..." && \
    curl -f -L --retry 3 --retry-delay 5 --max-time 300 \
        "https://akkoma-updates.s3-website.fr-par.scw.cloud/${AKKOMA_VERSION}/akkoma-${AKKOMA_FLAVOUR}.zip" \
        -o akkoma.zip && \
    unzip -q akkoma.zip || (echo "ERROR: Failed to extract release archive"; exit 1) && \
    rm akkoma.zip

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
FROM alpine:3.19

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

# Create akkoma user and group (UID/GID 1000)
# Running as non-root user for security
RUN addgroup -g 1000 akkoma && \
    adduser -D -u 1000 -G akkoma akkoma

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
