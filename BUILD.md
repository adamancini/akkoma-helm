# Akkoma Container Image - Build Guide

This document provides instructions for building the Akkoma OTP release container image.

## Image Overview

- **Base Images:**
  - Builder stage: `elixir:1.14-alpine`
  - Runtime stage: `alpine:3.19`
- **Build Time:** 10-15 minutes (first build, no cache)
- **Image Size:** ~200MB
- **Architecture:** amd64 (arm64 support deferred to v0.2.0)
- **User:** Non-root (akkoma:akkoma, UID/GID 1000)
- **Port:** 4000

## Build Arguments

### AKKOMA_VERSION

Git reference to build from the Akkoma repository.

**Accepted values:**
- Tags: `v3.13.2`, `v3.12.0`, etc.
- Branches: `stable`, `develop`
- Commits: Full commit SHA

**Default:** `v3.13.2`

## Build Commands

### Basic Build (Latest Stable)

```bash
docker build -t akkoma:latest .
```

### Build Specific Version

```bash
docker build -t akkoma:v3.13.2 --build-arg AKKOMA_VERSION=v3.13.2 .
```

### Build from Branch

```bash
docker build -t akkoma:develop --build-arg AKKOMA_VERSION=develop .
```

### Build with Custom Tag

```bash
docker build -t ghcr.io/adamancini/akkoma:v3.13.2 \
  --build-arg AKKOMA_VERSION=v3.13.2 .
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

### Stage 1: Builder

1. Base: `elixir:1.14-alpine`
2. Install build dependencies:
   - git (source code retrieval)
   - build-base (C compiler toolchain)
   - cmake (build system)
   - postgresql-client (database tools)
3. Clone Akkoma source at specified version
4. Install Hex and Rebar (Elixir/Erlang package managers)
5. Fetch production dependencies (separate layer for caching)
6. Compile and build OTP release
7. **Verify release creation** - Confirms `_build/prod/rel/pleroma` exists

**Release Name Verification:**
The OTP release name is `pleroma` as defined in Akkoma's `mix.exs` file:
```elixir
releases: [
  pleroma: [
    include_executables_for: [:unix],
    applications: [ex_syslogger: :load, syslog: :load, eldap: :transient],
    steps: [:assemble, &put_otp_version/1, &copy_files/1, &copy_nginx_config/1],
    config_providers: [{Pleroma.Config.ReleaseRuntimeProvider, []}]
  ]
]
```

This creates the release at `_build/prod/rel/pleroma/` with the executable at `bin/pleroma`.

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
4. Copy OTP release from builder
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

Expected: ~200MB (compressed)

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

### Dependency Caching

The Dockerfile separates `mix deps.get` from `mix compile` to improve build caching:

- **Layer 1:** `mix deps.get --only prod` - Cached unless dependencies change
- **Layer 2:** `mix do compile, release` - Re-runs when source code changes

This optimization significantly reduces rebuild time when iterating on Akkoma source.

### Using Build Cache

Docker caches layers for faster rebuilds. To maximize cache efficiency:

```bash
# Clean build (no cache)
docker build --no-cache -t akkoma:latest .

# Use cache from previous build
docker build -t akkoma:latest .
```

### Build Arguments for CI/CD

```bash
# GitHub Actions example
docker build \
  -t ghcr.io/${{ github.repository }}/akkoma:${{ github.sha }} \
  -t ghcr.io/${{ github.repository }}/akkoma:latest \
  --build-arg AKKOMA_VERSION=v3.13.2 \
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

### Build Fails: Git Clone

**Error:** `fatal: unable to access 'https://akkoma.dev/...': Could not resolve host`

**Solution:** Check network connectivity, firewall rules, DNS resolution

### Build Fails: Mix Dependencies

**Error:** `** (Mix) Could not fetch dependency`

**Solution:** Build dependencies may be temporarily unavailable. Retry build.

### Build Fails: OTP Release

**Error:** `** (Mix) Release failed`

**Solution:** Check Elixir/Erlang version compatibility, review build logs

### Build Fails: Release Verification

**Error:** `ERROR: OTP release not found at expected path`

**Cause:** The release name in `mix.exs` may have changed in a different Akkoma version.

**Solution:**
1. Check the build output for the actual release name
2. Look at the `releases:` section in `mix.exs` for the version being built
3. Verify the release was created: `ls -la _build/prod/rel/`
4. Update Dockerfile paths if release name differs from `pleroma`

**Expected:** For Akkoma v3.13.2 and compatible versions, the release name is `pleroma` as defined in `mix.exs:36`

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
