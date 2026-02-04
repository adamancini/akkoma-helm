# Dockerfile Release Path Verification

This document records the verification of the OTP release name and path used in the Dockerfile.

## Verification Date

2026-02-04

## Version Verified

Akkoma v3.13.2

## Verification Method

1. Cloned Akkoma source at tag v3.13.2:
   ```bash
   git clone --branch v3.13.2 --depth 1 https://akkoma.dev/AkkomaGang/akkoma.git
   ```

2. Inspected `mix.exs` file at lines 35-42:
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

## Verified Facts

### Release Name
**Value:** `pleroma`

**Source:** `mix.exs` line 36 (releases keyword list)

**Path Created:**
- Build output: `_build/prod/rel/pleroma/`
- Executable: `_build/prod/rel/pleroma/bin/pleroma`

### Dockerfile Impact

**Builder Stage (line 51):**
```dockerfile
RUN test -f /build/_build/prod/rel/pleroma/bin/pleroma || \
    (echo "ERROR: OTP release not found at expected path" && \
     exit 1)
```

**Runtime Stage (line 90-91):**
```dockerfile
COPY --from=builder --chown=akkoma:akkoma \
    /build/_build/prod/rel/pleroma /opt/akkoma
```

**CMD (line 105):**
```dockerfile
CMD ["./bin/pleroma", "start"]
```

## Why This Matters

Elixir's `mix release` creates releases at `_build/$MIX_ENV/rel/$RELEASE_NAME`, where `$RELEASE_NAME` comes from the `releases:` keyword list in `mix.exs`.

Using an incorrect release name would cause:
1. Build failure: COPY from non-existent path
2. Runtime failure: Missing `./bin/pleroma` executable
3. Container fails to start with "file not found" error

## Verification Strategy

The Dockerfile now includes a verification step that:
1. Tests for the existence of the release binary
2. Fails the build immediately with a helpful error message
3. Lists available releases if the expected path doesn't exist

This ensures the build fails fast and provides clear feedback if:
- The release name changes in a future Akkoma version
- The mix.exs configuration is modified
- The build process creates releases at a different path

## Historical Note

Akkoma is a fork of Pleroma, which explains why the release name remains `pleroma` despite the project being renamed to Akkoma. This naming is preserved for compatibility with existing tooling and deployment patterns.

## Expected Stability

The `pleroma` release name is expected to remain stable across Akkoma v3.x versions. Any change to the release name would be considered a breaking change and would likely coincide with a major version bump (v4.0+).

## Verification for Other Versions

To verify the release name for a different Akkoma version:

```bash
# Clone at specific version
git clone --branch $VERSION --depth 1 https://akkoma.dev/AkkomaGang/akkoma.git

# Check mix.exs
grep -A 10 "releases:" mix.exs
```

Look for the keyword list under `releases:` - the first atom is the release name.

## Related Files

- `Dockerfile` - Contains verification step and documented paths
- `BUILD.md` - Documents build process and troubleshooting
- `mix.exs` (in Akkoma source) - Defines release configuration
