# Akkoma Container Image - Build Guide

This document provides instructions for building the Akkoma OTP release container image.

## Image Overview

- **Base Image:** `alpine:3.19`
- **Build Method:** Downloads pre-built OTP release from Akkoma update server
- **Build Time:** 1-2 minutes (download only)
- **Image Size:** ~91MB
- **Architecture:** amd64-musl (Alpine Linux)
- **User:** Non-root (akkoma:akkoma, UID/GID 1000)
- **Port:** 4000

## Build Arguments

### AKKOMA_VERSION

Release version to download from the Akkoma update server.

**Accepted values:**
- `stable` - Latest stable release (recommended)
- `develop` - Development/unstable branch
- Version tags: `v3.17.0`, `v3.16.0`, etc. (if pre-built)

**Default:** `stable`

### AKKOMA_FLAVOUR

Platform flavour determines the build architecture.

**Accepted values:**
- `amd64-musl` - Alpine Linux x86_64 (default)
- `arm64-musl` - Alpine Linux aarch64
- `amd64` - Debian/Ubuntu x86_64
- `arm64` - Debian/Ubuntu aarch64

**Default:** `amd64-musl`

**Note:** Only `amd64-musl` is currently tested and supported for this container image.

## Build Commands

### Basic Build (Latest Stable)

```bash
docker build -t akkoma:latest .
```

This downloads the `stable` branch pre-built release (currently v3.17.0).

### Build Specific Version

```bash
docker build -t akkoma:v3.17.0 --build-arg AKKOMA_VERSION=stable .
```

### Build from Development Branch

```bash
docker build -t akkoma:develop --build-arg AKKOMA_VERSION=develop .
```

### Build with Custom Tag

```bash
docker build -t ghcr.io/adamancini/akkoma:v3.17.0 \
  --build-arg AKKOMA_VERSION=stable .
```

## Multi-Platform Builds

For multi-architecture support (requires Docker Buildx):

```bash
# Create buildx builder (one-time setup)
docker buildx create --name akkoma-builder --use

# Build for multiple platforms
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t ghcr.io/adamancini/akkoma:v3.13.2 \
  --build-arg AKKOMA_VERSION=v3.13.2 \
  --push \
  .
```

**Note:** Multi-arch support is deferred to v0.2.0 of the Helm chart.

## Image Layers

### Stage 1: Downloader

1. Base: `alpine:3.19`
2. Install download dependencies:
   - curl (HTTP client)
   - unzip (archive extraction)
3. Download pre-built OTP release from Akkoma update server:
   - URL: `https://akkoma-updates.s3-website.fr-par.scw.cloud/${AKKOMA_VERSION}/akkoma-${AKKOMA_FLAVOUR}.zip`
   - Default: `stable` branch, `amd64-musl` flavour
4. Extract release archive
5. **Verify release structure** - Confirms `release/` directory exists

**Release Structure:**
The pre-built OTP release contains:
- `bin/pleroma` - Main application binary
- `bin/pleroma_ctl` - Administrative control script
- `lib/` - Compiled BEAM bytecode and dependencies
- `releases/` - Release metadata and configuration
- `erts-*/` - Erlang Runtime System

### Stage 2: Runtime

1. Base: `alpine:3.19`
2. Install runtime dependencies:
   - ncurses-libs (BEAM VM requirement)
   - postgresql-client (database connectivity)
   - imagemagick (image processing)
   - ffmpeg (video processing)
   - exiftool (metadata extraction)
   - libmagic, file (file type detection)
   - ca-certificates, openssl (TLS/HTTPS)
3. Create akkoma user/group (UID/GID 1000)
4. Copy pre-built OTP release from downloader stage
5. Set working directory and user
6. Expose port 4000

## Runtime Requirements

### Required Environment Variables

The container requires configuration at runtime. These are typically provided by Kubernetes:

```bash
# Database configuration
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_USER=akkoma
POSTGRES_PASSWORD=secret
POSTGRES_DB=akkoma

# Application configuration
SECRET_KEY_BASE=<generated-secret>
SIGNING_SALT=<generated-salt>
DOMAIN=example.com
```

### Volume Mounts

Required persistent storage:

- `/opt/akkoma/uploads` - User-uploaded media files
- `/opt/akkoma/config/prod.secret.exs` - Application configuration

### Port Exposure

- **4000/tcp** - HTTP application port (Akkoma web interface and API)

## Testing the Image

### Quick Test Run

```bash
# Run with minimal configuration (will fail without database)
docker run --rm -it akkoma:latest
```

### Test with PostgreSQL

```bash
# Start PostgreSQL
docker run -d --name postgres \
  -e POSTGRES_USER=akkoma \
  -e POSTGRES_PASSWORD=akkoma \
  -e POSTGRES_DB=akkoma \
  postgres:16-alpine

# Start Akkoma (after proper configuration)
docker run -d --name akkoma \
  --link postgres:postgres \
  -e POSTGRES_HOST=postgres \
  -e POSTGRES_USER=akkoma \
  -e POSTGRES_PASSWORD=akkoma \
  -e POSTGRES_DB=akkoma \
  -p 4000:4000 \
  akkoma:latest
```

**Note:** This is a simplified test. Production deployment requires:
- Proper configuration file (`prod.secret.exs`)
- Database initialization
- Frontend installation
- Reverse proxy

## Verification Steps

After building, verify the image:

### 1. Check Image Size

```bash
docker images akkoma:latest
```

Expected: ~91MB (actual size may vary by a few MB depending on release version)

### 2. Inspect Image Metadata

```bash
docker inspect akkoma:latest
```

Verify:
- User: `akkoma` (UID 1000)
- Working directory: `/opt/akkoma`
- Exposed ports: 4000
- CMD: `["./bin/pleroma", "start"]`

### 3. Check Binary Exists

```bash
docker run --rm akkoma:latest ls -lh /opt/akkoma/bin/pleroma
```

Expected: Executable file owned by akkoma

### 4. Verify Runtime Dependencies

```bash
docker run --rm akkoma:latest sh -c "command -v ffmpeg && command -v convert && command -v exiftool"
```

Expected: All commands found

### 5. Check Erlang/BEAM VM

```bash
docker run --rm akkoma:latest ./bin/pleroma version
```

Expected: Version information or error about missing configuration (acceptable)

## Build Optimization

### Download Caching

The Dockerfile uses a two-stage build to minimize image size:

- **Stage 1 (Downloader):** Downloads and extracts the OTP release
- **Stage 2 (Runtime):** Contains only runtime dependencies and the release

Docker caches the download layer, so rebuilds are fast unless the `AKKOMA_VERSION` changes.

### Using Build Cache

```bash
# Clean build (no cache)
docker build --no-cache -t akkoma:latest .

# Use cache from previous build (recommended)
docker build -t akkoma:latest .
```

The download will be cached and reused if the version hasn't changed.

### Build Arguments for CI/CD

```bash
# GitHub Actions example
docker build \
  -t ghcr.io/${{ github.repository }}/akkoma:${{ github.sha }} \
  -t ghcr.io/${{ github.repository }}/akkoma:latest \
  --build-arg AKKOMA_VERSION=stable \
  .
```

## Security Considerations

### Non-Root User

The image runs as user `akkoma` (UID 1000) for security:

```bash
# Verify non-root
docker run --rm akkoma:latest id
# Expected: uid=1000(akkoma) gid=1000(akkoma)
```

### No HEALTHCHECK

This image intentionally does **not** include a Docker HEALTHCHECK directive. Kubernetes provides superior probe mechanisms:

- **startupProbe** - Allows up to 150s for initial startup
- **livenessProbe** - Detects when container needs restart
- **readinessProbe** - Determines when pod is ready for traffic

### CVE Scanning

Scan the image for vulnerabilities:

```bash
# Using Trivy
trivy image akkoma:latest

# Using Docker Scout
docker scout cves akkoma:latest
```

## Troubleshooting

### Build Fails: Download Error

**Error:** `curl: (22) The requested URL returned error: 404`

**Cause:** The requested version or flavour doesn't have a pre-built release.

**Solution:**
1. Check available releases at: https://akkoma-updates.s3-website.fr-par.scw.cloud/
2. Use `stable` or `develop` branches (always available)
3. Verify the AKKOMA_FLAVOUR matches your target platform

### Build Fails: Release Verification

**Error:** `ERROR: Release directory not found`

**Cause:** The downloaded archive doesn't contain the expected `release/` directory.

**Solution:**
1. Check the download URL is accessible
2. Verify the archive isn't corrupted
3. Check network connectivity to S3 bucket
4. Try rebuilding with `--no-cache`

### Runtime: Missing Configuration

**Error:** `Config file not found`

**Solution:** Mount configuration file at `/opt/akkoma/config/prod.secret.exs`

### Runtime: Database Connection

**Error:** `connection refused` or `database does not exist`

**Solution:**
1. Verify PostgreSQL is running
2. Check database credentials
3. Ensure database is initialized
4. Run migrations

## Next Steps

After building the image:

1. **Push to Registry** - See Task #3 (Push to GitHub Container Registry)
2. **Local Testing** - See Task #2 (Build and test locally)
3. **Helm Chart Integration** - Update `values.yaml` with image reference

## References

- [Akkoma Documentation](https://docs.akkoma.dev/)
- [Docker Multi-Stage Builds](https://docs.docker.com/build/building/multi-stage/)
- [Elixir Releases](https://hexdocs.pm/mix/Mix.Tasks.Release.html)
- [Alpine Linux Packages](https://pkgs.alpinelinux.org/packages)
