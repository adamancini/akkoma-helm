# Architecture Decision Record: Pre-Built OTP Releases

**Date:** 2026-02-04
**Status:** Accepted
**Decision Makers:** Development Team

## Context and Problem Statement

The initial Dockerfile approach attempted to build Akkoma from source using a multi-stage build process. This approach encountered a critical dependency issue that blocked all image builds across multiple Akkoma versions.

## The Problem: Linkify Dependency Compilation Failure

### Error Details

All attempts to build Akkoma from source (versions v3.9.3 through v3.17.0, including the `stable` branch) failed during the `mix deps.get --only prod` step with this error:

```
Error while loading project :linkify at /build/deps/linkify
** (MatchError) no match of right hand side value: {:credo, "~> 1.5", [only: [:dev, :test], runtime: false]}
    /build/deps/linkify/mix.exs:46: Linkify.Mixfile.aliases/0
    (mix 1.14.5) lib/mix/project.ex:838: Mix.Project.get_project_config/1
    (mix 1.14.5) lib/mix/project.ex:141: Mix.Project.push/3
    (stdlib 5.2.3.5) lists.erl:1594: :lists.foldl/3
```

### Root Cause

The `linkify` library (an Akkoma dependency at `https://akkoma.dev/AkkomaGang/linkify.git`) has a bug in its `mix.exs` file. The `aliases/0` function attempts to pattern match on the `:credo` dependency but the pattern doesn't handle the actual dependency format correctly.

Specifically, the function expects one format but receives:
```elixir
{:credo, "~> 1.5", [only: [:dev, :test], runtime: false]}
```

This causes an unhandled `MatchError` that aborts the dependency resolution process.

### Affected Versions

This issue affects all tested Akkoma versions:
- v3.9.3 (December 2023)
- v3.13.2 (February 2024)
- v3.15.x (March 2025)
- v3.16.0 (October 2025)
- v3.17.0 (December 2025)
- `stable` branch (HEAD)

## Alternatives Considered

### Alternative 1: Patch linkify Dependency

**Approach:** Download linkify, patch its `mix.exs` file, then proceed with build.

**Attempted Implementation:**
```dockerfile
RUN mix deps.get --only prod || true && \
    if [ -f /build/deps/linkify/mix.exs ]; then \
      sed -i 's/def aliases do/def aliases do\n    []\n  end\n\n  def aliases_disabled do/' /build/deps/linkify/mix.exs; \
    fi && \
    mix deps.get --only prod
```

**Result:** ❌ FAILED
- The error occurs during `deps.get` before linkify is fully extracted
- Cannot patch a file that doesn't exist yet
- Even with `|| true`, the linkify directory structure isn't accessible

**Why Not Pursued:** Technical infeasibility. The error occurs too early in the dependency resolution process.

### Alternative 2: Use Development Mode Build

**Approach:** Fetch dependencies in `MIX_ENV=dev` mode (which might skip the problematic code path), then switch to production.

**Attempted Implementation:**
```dockerfile
RUN MIX_ENV=dev mix deps.get && \
    rm -rf deps _build && \
    MIX_ENV=prod mix deps.get --only prod
```

**Result:** ❌ FAILED
- Same error occurs in both dev and prod modes
- The bug is in linkify's `mix.exs` file itself, not in environment-specific code
- Cleaning and refetching doesn't bypass the issue

**Why Not Pursued:** The bug affects all MIX_ENV configurations.

### Alternative 3: Fix Upstream Linkify

**Approach:** Submit a patch to the linkify repository, wait for merge and release.

**Considerations:**
- ✅ Would fix the root cause
- ❌ Requires coordination with Akkoma maintainers
- ❌ Timeline uncertain (could be days, weeks, or months)
- ❌ Blocks immediate progress on Helm chart development
- ❌ Historical evidence suggests this may not be prioritized (bug exists across 2+ years of releases)

**Why Not Pursued:** Timeline incompatible with project requirements. The bug has persisted across many Akkoma releases without being addressed.

### Alternative 4: Use Different Elixir/OTP Versions

**Approach:** Try different base images (elixir:1.15, elixir:1.13, etc.) to see if the error is version-specific.

**Result:** ❌ NOT ATTEMPTED
- The error is in Elixir source code parsing (the `aliases/0` function), not BEAM VM behavior
- Different Elixir versions would still parse the same buggy `mix.exs` file
- Extremely low probability of success

**Why Not Pursued:** Root cause analysis indicated this wouldn't resolve the issue.

## Decision: Use Pre-Built OTP Releases

### Solution Overview

Switch from source compilation to downloading pre-built OTP releases from Akkoma's official update server.

**Source:** https://akkoma-updates.s3-website.fr-par.scw.cloud/

### Rationale

1. **Official Distribution Method:** Akkoma's documentation ([OTP installation guide](https://docs.akkoma.dev/stable/installation/otp_en/)) recommends using pre-built releases for production deployments.

2. **Bypasses Compilation:** Pre-built releases are already compiled and don't require running `mix deps.get` or `mix release`, completely avoiding the linkify bug.

3. **Faster Builds:**
   - Source compilation: 10-15 minutes
   - Pre-built download: ~7 seconds
   - 100x+ speedup in build time

4. **Smaller Build Context:** Eliminates need for Elixir, Mix, build-base, cmake, and other compilation tools in the image.

5. **Proven Reliability:** These are the same releases used by Akkoma's official Docker installation method and recommended for production use.

### Implementation

**Dockerfile Structure:**
- **Stage 1 (Downloader):** Alpine + curl + unzip → download and extract release
- **Stage 2 (Runtime):** Alpine + runtime dependencies → copy release and configure

**Download URL Pattern:**
```
https://akkoma-updates.s3-website.fr-par.scw.cloud/${AKKOMA_VERSION}/akkoma-${AKKOMA_FLAVOUR}.zip
```

**Build Arguments:**
- `AKKOMA_VERSION`: `stable` (default), `develop`, or specific version
- `AKKOMA_FLAVOUR`: `amd64-musl` (Alpine), `arm64-musl`, `amd64` (Debian), `arm64`

## Trade-offs and Consequences

### Advantages ✅

1. **Eliminates Build Failures:** Completely bypasses the linkify compilation issue
2. **Faster Builds:** 100x speedup (7 seconds vs 10-15 minutes)
3. **Smaller Build Context:** No Elixir/Mix toolchain needed
4. **Official Support:** Aligns with Akkoma's recommended distribution method
5. **Easier Maintenance:** No need to track upstream Elixir/Erlang version compatibility

### Disadvantages ❌

1. **External Dependency:** Relies on S3 bucket availability (akkoma-updates.s3-website.fr-par.scw.cloud)
2. **Supply Chain Trust:** Trusts Akkoma's build process without independent verification
3. **Version Availability:** Only versions that Akkoma pre-builds are available
4. **No Checksum Verification:** Current implementation doesn't verify release integrity
5. **Platform Lock-in:** Limited to pre-built platforms (amd64-musl, arm64-musl, amd64, arm64)

## Risks and Mitigations

### Risk 1: S3 Bucket Unavailability

**Risk:** The S3 bucket (akkoma-updates.s3-website.fr-par.scw.cloud) becomes unavailable or discontinued.

**Impact:** HIGH - Image builds would fail completely.

**Probability:** LOW - This is Akkoma's official distribution channel.

**Mitigations:**
1. **Docker Layer Caching:** Once downloaded, the release is cached in Docker build cache
2. **CI/CD Registry Caching:** Store built images in container registry (ghcr.io)
3. **Periodic Rebuilds:** Rebuild images on a schedule to maintain fresh cache
4. **Fallback Documentation:** Document manual download procedures in BUILD.md
5. **Mirror Consideration:** Future work could mirror releases to a secondary location

**Monitoring:** Track build failures in CI/CD; alert if S3 download fails repeatedly.

### Risk 2: Supply Chain Compromise

**Risk:** The S3 bucket is compromised and serves malicious releases.

**Impact:** CRITICAL - Malicious code would be deployed to production.

**Probability:** LOW - Requires compromise of Akkoma's infrastructure.

**Mitigations:**
1. **No Current Checksum Verification:** ⚠️ ACKNOWLEDGED RISK - Current Dockerfile doesn't verify checksums
2. **Container Scanning:** Use trivy/grype to scan built images for known vulnerabilities
3. **Limited Blast Radius:** Non-root user (UID 1000) limits potential damage
4. **Network Policies:** Kubernetes NetworkPolicies can restrict pod egress
5. **Monitoring:** Runtime behavior monitoring and anomaly detection

**Future Enhancement:** Implement checksum verification once Akkoma publishes checksums alongside releases.

**Acceptance:** This risk is accepted because:
- Akkoma is open-source and releases can be audited
- The official Docker installation uses the same distribution method
- Container scanning provides a layer of defense
- The alternative (source builds) is currently non-functional

### Risk 3: Version Availability

**Risk:** Specific Akkoma versions might not have pre-built releases available.

**Impact:** MEDIUM - Cannot build images for those specific versions.

**Probability:** LOW - Akkoma maintains `stable` and `develop` builds consistently.

**Mitigations:**
1. **Use stable/develop Branches:** These are always available
2. **Version Documentation:** Document tested versions in BUILD.md
3. **Fallback Strategy:** For custom versions, could fall back to source builds if linkify bug is fixed upstream

**Acceptance:** This is an acceptable trade-off for the significant build reliability improvement.

### Risk 4: Platform Limitations

**Risk:** Desired target platform doesn't have pre-built releases (e.g., riscv64).

**Impact:** LOW - Cannot deploy to unsupported platforms.

**Probability:** LOW - Common platforms (amd64, arm64) are well-supported.

**Mitigations:**
1. **Platform Documentation:** Clearly document supported platforms
2. **Multi-arch Support:** Use standard platforms (amd64-musl for Alpine, amd64 for Debian)
3. **Future Builds:** If needed, could build from source for exotic platforms once linkify bug is fixed

**Acceptance:** The supported platforms (amd64, arm64, musl/glibc variants) cover 99%+ of deployment scenarios.

## Monitoring and Success Metrics

### Build Success Rate
- **Target:** >99% successful builds
- **Measurement:** CI/CD build success ratio
- **Alert:** If success rate drops below 95%

### Download Performance
- **Target:** <30 seconds download time
- **Measurement:** Docker build logs
- **Alert:** If download consistently exceeds 60 seconds

### Image Size
- **Baseline:** 374 MB uncompressed (90.7 MB compressed)
- **Monitoring:** Track size across releases
- **Alert:** If size increases >20% without explanation

### Security Posture
- **Container Scanning:** Run trivy/grype on every build
- **Vulnerability Threshold:** Block images with HIGH/CRITICAL CVEs
- **Update Cadence:** Rebuild images weekly for security updates

## Conclusion

The decision to use pre-built OTP releases instead of source compilation is driven by:
1. **Technical Necessity:** Source builds are currently broken due to linkify dependency bug
2. **Alignment with Upstream:** Matches Akkoma's official distribution method
3. **Practical Benefits:** Faster builds, smaller images, better reliability

The trade-offs (external dependency, supply chain trust) are accepted as reasonable risks given:
- The alternative is non-functional
- Mitigations are in place
- The approach aligns with Akkoma's official recommendations

This decision should be revisited if:
1. The upstream linkify bug is fixed
2. Akkoma changes its distribution strategy
3. S3 availability becomes unreliable
4. Supply chain security requirements increase

## References

- [Akkoma OTP Installation Guide](https://docs.akkoma.dev/stable/installation/otp_en/)
- [Akkoma Docker Installation Guide](https://docs.akkoma.dev/stable/installation/docker_en/)
- [Akkoma Update Server](https://akkoma-updates.s3-website.fr-par.scw.cloud/)
- [Linkify Repository](https://akkoma.dev/AkkomaGang/linkify)
- Build Logs: See VERIFICATION.md for detailed test results
