---
name: buildpacks-domain
description: This skill should be used when working in Cloud Foundry buildpacks repositories (buildpacks/*, libbuildpack, switchblade, buildpacks-ci, binary-builder, buildpacks-release) to provide architectural context about the buildpack ecosystem, libbuildpack contracts, testing patterns, CI/CD conventions, and multi-repo search strategies.
---

# Cloud Foundry Buildpacks Domain Knowledge

Use when changing buildpack code, `libbuildpack` contracts, manifests, integration tests, or CI config, or when debugging staging.
Details and code samples: `references/architecture.md`.

## Architecture

```
CF platform -> language buildpack (Go + bash wrappers) -> libbuildpack (shared Go lib)
            -> manifest.yml -> buildpacks.cloudfoundry.org (compiled dependencies)
```

- **libbuildpack**: shared library (Manifest, Installer, Stager, Logger). Changes affect every language buildpack, so read it first.
- **Language buildpacks**: go, python, ruby, php, nodejs, java (Go-based), dotnet-core, staticfile, binary, apt, nginx, r, hwc.
- **switchblade**: integration test framework for CF and Docker.
- **buildpacks-ci**: Concourse pipelines (ytt) and the dependency bot.
- **binary-builder**: compiles dependencies per stack.
- **buildpacks-release**: BOSH release, one package per buildpack and stack.

## Lifecycle

Scripts get positional args from CF: `bin/detect <build>`, `bin/supply <build> <cache> <deps> <idx>`, `bin/finalize <build> <cache> <deps> <idx> <profile>`, `bin/release <build>`.
- Order: detect, supply (all buildpacks), finalize (last only), release.
- `DEPS_IDX` isolates each buildpack in `$DEPS_DIR/<idx>/`. Supply buildpacks pass data to the final one via `config.yml` (schema is buildpack-specific).
- Typical `bin/*` is a bash script (not POSIX sh) that builds and runs a Go binary. Non-zero exit means failure; specific codes are buildpack-defined.

## Manifest and stacks

- `manifest.yml` lists dependencies (name, version, uri, sha256, cf_stacks, source, source_sha256).
- Dependencies are filtered by the `CF_STACK` env var at runtime and by the packager at package time.
- `AllDependencyVersions` and `GetEntry` filter by stack. `InstallOnlyVersion*` fails with "more than one version of X found" if a stack sees two versions of one dependency.
- Stacks: cflinuxfs4 (current), cflinuxfs5 (becomes the default once fs4 is deprecated, planned next year), cflinuxfs3 (deprecated, superseded by fs4).
- Manifest entries are updated by bot PRs (from buildpacks-ci). Check which stacks a bumped entry lists before merging.

## Dependency installation

1. Cached buildpack: file in `dependencies/` (offline).
2. App cache: `$CACHE_DIR/dependencies`, keyed by SHA256 of the URI (needs `SetAppCacheDir`).
3. Remote download from the manifest URI. SHA256 is always verified.

## Testing

- **Unit**: Go packages with mocks (`scripts/unit.sh`).
- **Integration**: switchblade, same test on CF or Docker (`scripts/integration.sh`). Fixtures live in `fixtures/`.
- **BRATS**: configured in buildpacks-ci and the buildpack repos but not used (`skip_brats: true` for all buildpacks, not in PR workflows). Do not rely on it.

## CI (buildpacks-ci)

- `pipelines/dependency-builds`: builds dependencies and opens manifest bump PRs. `config.yml` maps each dependency to its buildpacks and version lines; a dependency used by several buildpacks is shared across them.
- `pipelines/buildpack`: per-buildpack unit, integration, package, release. Per-buildpack options live in `*-values.yml`.
- Also: rootfs (cflinuxfs) pipelines and CVE checks.

## Searching

Search the local clone of `libbuildpack` first, then the language buildpacks:

```bash
rg "libbuildpack\." <clones>/buildpacks/        # usage across buildpacks
rg "func .*Manifest" <clones>/libbuildpack/     # API
rg "platform\.Deploy" <clones>/*/src/*/integration/
```

Repos not cloned locally: search on GitHub (`org:cloudfoundry`). Other repos: the packager lives in `libbuildpack/packager` (the standalone buildpack-packager repo is an old Ruby gem, last pushed 2023). machete and compile-extensions are archived.

## Legacy names

`io.pivotal` and similar names are historical. Rename only when verified safe: they are baked into compiled test fixtures, and `io.pivotal.cfenv` is the real Maven group of java-cfenv (in `manifest.yml` URLs). Prefer replacing a legacy fixture over renaming it. Also historical: VMware in doc prose, `springsource` doc links (the old Spring host, dead links, replace with spring.io when the page is touched), `pivotal.io` emails. Boy scout rule: trivial fixes only, in files the PR already touches.

## Pitfalls

- Packager: needs a real `.git` dir (not a worktree). java-buildpack: build the gitignored `bin/javaexec` first.
- Packager download cache `~/.buildpack-packager/cache` is keyed by URI, so a floating URL (`/latest/`) can leave a stale file and a false sha256 mismatch. Use versioned URIs.
- switchblade Docker mode (Java apps): explode jars into a directory before `Execute`.
- `go test -run` splits the pattern on `/`: one regex per test level, no `|` across levels.
- Date-based versions are not really supported by `libbuildpack`.

## Before changing things

1. Check whether the change touches `libbuildpack` or the manifest format (affects all buildpacks).
2. Check cached (offline) and uncached behavior, and multi-buildpack `DEPS_IDX` isolation.
3. Check each stack the manifest lists for the changed dependency.
4. When debugging, read staging logs first, then check cache tier, SHA256 mismatch, stack compatibility.
