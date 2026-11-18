# Buildpacks Architecture: Contracts and Code Patterns

Companion to `SKILL.md`. API signatures (libbuildpack, switchblade) and the packager invocation were checked against their sources. Lifecycle and CI notes are carried over from the earlier version and not all re-verified.

## libbuildpack components

| Component | Key API |
|---|---|
| Manifest (`manifest.go`) | `NewManifest(bpDir, logger, time)`, `DefaultVersion(name)`, `AllDependencyVersions(name)`, `GetEntry(dep)`, `IsCached()`, `CheckStackSupport()` |
| Installer (`installer.go`) | `NewInstaller(manifest)`, `SetAppCacheDir(dir)`, `InstallDependency(dep, dir)`, `InstallDependencyWithStrip(dep, dir, n)`, `InstallOnlyVersion(name, dir)`, `InstallOnlyVersionWithStrip`, `CleanupAppCache()` |
| Stager (`stager.go`) | `NewStager(args, logger, manifest)`, `BuildDir()`, `CacheDir()`, `DepsDir()`, `DepDir()`, `DepsIdx()` (a **string**), `WriteEnvFile`, `WriteProfileD`, `LinkDirectoryInDepDir` |
| Logger (`logger.go`) | `NewLogger(w)`, `Info`, `Debug`, `Warning`, `Error`, `BeginStep` |

Notes:
- The current stack is the `CF_STACK` env var. `Manifest.Stack` is a field (a `stack:` value in the manifest), not a method.
- `Installer` extracts `.zip` and tarballs, and can strip leading path components. It also warns on newer patch versions and end-of-life dependencies.

### Standard initialization

```go
logger := libbuildpack.NewLogger(os.Stdout)
buildpackDir, err := libbuildpack.GetBuildpackDir()
manifest, err := libbuildpack.NewManifest(buildpackDir, logger, time.Now())
stager := libbuildpack.NewStager(os.Args[1:], logger, manifest)
installer := libbuildpack.NewInstaller(manifest)
installer.SetAppCacheDir(stager.CacheDir())
defer installer.CleanupAppCache()

dep, err := manifest.DefaultVersion("python")
err = installer.InstallDependency(dep, filepath.Join(stager.DepDir(), "python"))
err = stager.WriteProfileD("python.sh", "export PATH=...")
```

## Lifecycle details

- **detect**: exit 0 and print a name if the buildpack applies, otherwise exit non-zero. Do not write files.
- **supply** (all buildpacks): install into `$DEPS_DIR/$DEPS_IDX/`; optionally write `config.yml` for the final buildpack. Non-destructive to the app dir.
- **finalize** (last buildpack only): gets a 5th arg `PROFILE_DIR`. Reads the other buildpacks' `config.yml`, modifies the app, writes startup config.
- **release**: print YAML (`default_process_types`, optional `config_vars`).
- profile.d scripts run at container start; keep them idempotent.

Multi-buildpack layout: `$DEPS_DIR/0/`, `1/`, ... each with `bin/`, `lib/`, `include/`, `env/`, optional `config.yml`. The final buildpack iterates earlier indexes:

```go
for idx := 0; idx < finalIdx; idx++ { // finalIdx from strconv.Atoi(stager.DepsIdx())
    path := filepath.Join(stager.DepsDir(), strconv.Itoa(idx), "config.yml")
    ...
}
```

Common issues: `config.yml` schema mismatch, missing config, hardcoded paths instead of `DEPS_IDX`.

## Caching tiers

1. **Buildpack cache**: `manifest.IsCached()`; files in `dependencies/`.
2. **App cache**: `$CACHE_DIR/dependencies/<sha256(uri)>/<file>`; survives restages; cleaned by `CleanupAppCache`.
3. **Remote**: download from URI, verify SHA256, store in app cache if enabled.

## Stack filtering

```yaml
dependencies:
  - name: ruby
    version: 3.3.11
    uri: https://buildpacks.cloudfoundry.org/dependencies/ruby/ruby_..._cflinuxfs4_<sha8>.tgz
    sha256: ...
    cf_stacks: [cflinuxfs4]
    source: ...
    source_sha256: ...
```

- Runtime: `AllDependencyVersions`/`GetEntry` consider only entries listing the current `CF_STACK`.
- Packaging: `buildpack-packager` (Go, in `libbuildpack/packager`, installed with `go install`) builds per-stack artifacts: `buildpack-packager build --version=... --cached=... --stack=...`. Newer versions also support `--profile/--exclude/--include` for selective packaging. A buildpack's `scripts/package.sh` wraps it.
- Pitfall: `InstallOnlyVersion*` errors if a bump leaves two versions of one dependency for the same stack.

## Switchblade

```go
deployment, logs, err := platform.Deploy.
    WithBuildpacks("ruby_buildpack").
    WithEnv(map[string]string{"KEY": "value"}).
    Execute(name, "/path/to/app/source")
// logs: staging output; deployment.RuntimeLogs() returns (string, error)
defer platform.Delete.Execute(name)
```

Builder options: `WithBuildpacks`, `WithStack`, `WithEnv`, `WithoutInternetAccess`, `WithServices`, `WithStartCommand`, `WithHealthCheckType`. Assertions use matchers from `github.com/cloudfoundry/switchblade/matchers` (e.g. `Serve(...).WithEndpoint("/")`). `Platform` and `Deployment` are structs, not interfaces.

## CI notes (buildpacks-ci)

- `dependency-builds/config.yml`: per dependency, `buildpacks.<name>.lines`, `removal_strategy`, `versions_to_keep`, `skip_lines` (per dependency and stack; applies to every buildpack using that dependency). See `pipelines/dependency-builds/README.md`.
- Binaries are compiled in stack containers, so libc matches the stack; SHA256 is recorded and written into manifest bump PRs.
- Buildpack pipeline stages: unit, integration, package, release. BRATS is configured but not used (`skip_brats: true`).
