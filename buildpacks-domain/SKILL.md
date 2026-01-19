---
name: buildpacks-domain
description: This skill should be used when working in Cloud Foundry buildpacks repositories (buildpacks/*, libbuildpack, switchblade, buildpacks-ci, binary-builder, buildpacks-release) to provide architectural context about the buildpack ecosystem, libbuildpack contracts, testing patterns, CI/CD conventions, and multi-repo search strategies.
---

# Cloud Foundry Buildpacks Domain Knowledge

## When to Use This Skill

Use this skill when:
- Working in any buildpack-related repository in ~/workspace/cloudfoundry/
- Making changes that affect libbuildpack contracts or APIs
- Understanding buildpack lifecycle (detect, supply, finalize, release)
- Debugging buildpack staging or runtime issues
- Working with buildpack testing (Switchblade) or CI (buildpacks-ci)
- Understanding dependency management and caching strategies
- Searching for buildpack code across multiple repositories

## Architecture Overview

Cloud Foundry buildpacks follow a **shared library pattern** with libbuildpack at the center:

```
CF Platform
    ↓ (calls scripts with args)
Language Buildpack (Go/Ruby/Python/Java/etc.)
    ↓ (imports)
libbuildpack (shared Go library) ⭐ CRITICAL
    ↓ (reads)
manifest.yml (dependency declarations)
    ↓ (references)
buildpacks.cloudfoundry.org S3 (compiled dependencies)
```

### Key Components

- **libbuildpack** ⭐: Shared Go library providing Manifest, Installer, Stager, Logger
- **Language buildpacks**: Python, Ruby, Go, Java, PHP, Node.js, etc. (12+ buildpacks)
- **Switchblade**: Testing framework abstracting CF and Docker platforms
- **buildpacks-ci**: Concourse-based CI/CD pipelines
- **binary-builder**: Tool for compiling dependencies against specific stacks
- **buildpacks-release**: BOSH release packaging all buildpacks

## Buildpack Lifecycle Contracts

Buildpacks are **executable scripts** that CF Platform calls in sequence:

### Script Contracts

```bash
bin/detect <build-dir>
    # Exit 0 if buildpack applies, echo language name
    # Exit non-zero if not applicable

bin/supply <build> <cache> <deps> <idx>
    # Install buildpack dependencies
    # $1=BUILD_DIR, $2=CACHE_DIR, $3=DEPS_DIR, $4=DEPS_IDX

bin/finalize <build> <cache> <deps> <idx> <profile-dir>
    # Final configuration before app runs
    # $5=PROFILE_DIR contains startup scripts

bin/release <build-dir>
    # Echo YAML with runtime config (command, env vars)
```

**Key Contracts**:
- Arguments are positional (no flags)
- `DEPS_IDX` (integer) isolates buildpack files in multi-buildpack scenarios
- Exit codes matter: 0 = success, 8-19 = specific failure modes
- Scripts must be POSIX-compliant bash
- Order: Detect → Supply → Finalize → Release (sequential, not parallel)

### Common Pattern: Bash Wrapper → Go Binary

Modern buildpacks use this pattern:

```bash
# bin/supply (bash wrapper)
#!/bin/bash
go build -o /tmp/supply ./src/python/supply/cli
/tmp/supply "$@"
```

**Why?**: Compile Go binary fresh in staging environment, ensures isolation and picks up correct system libraries from rootfs.

## libbuildpack: The Core Contract

All language buildpacks import libbuildpack for standardized behavior.

### Four Core Components

#### 1. Manifest
- Parses `manifest.yml`
- Manages dependencies (name/version/URI/sha256/cf_stacks)
- Tracks deprecations
- Resolves version constraints (e.g., "3.2.x" → "3.2.2")
- File: `libbuildpack/manifest.go`

#### 2. Installer
- Three-tier dependency resolution
- Checksum verification (SHA256)
- Retry logic for downloads
- File: `libbuildpack/installer.go`

#### 3. Stager
- Manages staging directories (build/cache/deps)
- Writes environment variables
- Creates profile.d scripts for runtime
- File: `libbuildpack/stager.go`

#### 4. Logger
- Structured output (debug/info/warning/error)
- Colored terminal output
- File: `libbuildpack/logger.go`

### Initialization Pattern

All buildpacks follow this pattern:

```go
// 1. Load manifest from buildpack directory
manifest, err := libbuildpack.NewManifest(buildpackDir, logger, time.Now())

// 2. Create stager from CF-provided arguments
stager := libbuildpack.NewStager(os.Args[1:], logger, manifest)

// 3. Create installer and set app cache
installer := libbuildpack.NewInstaller(manifest)
installer.SetAppCacheDir(stager.CacheDir())

// 4. Install dependencies
err = installer.InstallDependency(dep, targetDir)

// 5. Write environment files
stager.WriteEnvFile("SOME_VAR", "value")
stager.WriteProfileD("setup.sh", content)

// 6. Clean up
defer installer.CleanupAppCache()
```

**Key Contract**: Every buildpack using libbuildpack follows this exact sequence.

## Three-Tier Caching Strategy

libbuildpack implements sophisticated dependency resolution:

### Tier 1: Buildpack Cache (Offline Mode)
- Dependencies bundled in buildpack zip in `dependencies/` directory
- Created by: `buildpack-packager build -cached=true`
- manifest has `file: dependencies/ruby_3.2.2.tgz` pointing to local paths
- Used in airgapped environments
- Check via: `manifest.IsCached()` returns true

### Tier 2: App Cache (Between Builds) ⭐ IMPORTANT
- Located at `$CACHE_DIR/dependencies/` (CF's persistent cache)
- Keyed by SHA256 hash of dependency URI
- Enabled via: `installer.SetAppCacheDir(cacheDir)`
- **Survives app restages** - avoids re-downloading same dependency
- Cleaned via: `installer.CleanupAppCache()` to remove unused files

### Tier 3: Remote Download
- Direct fetch from `manifest.yml` URI if not cached
- Always verified with SHA256 checksum before use

**Resolution Flow**:
```
1. Check Tier 1: manifest entry.File → Copy from buildpack directory
2. Check Tier 2: app cache → Copy from cache or download+cache
3. Tier 3: Direct download from URI (no caching)
```

**Why This Matters**: Apps without Tier 2 caching re-download 100MB+ on every staging (minutes vs seconds).

## Stack Filtering & Platform Contracts

### cf_stacks Field

Each dependency lists compatible stacks:

```yaml
dependencies:
  - name: ruby
    version: 3.2.2
    uri: https://buildpacks.cloudfoundry.org/dependencies/ruby/ruby_3.2.2_...cflinuxfs4.tgz
    sha256: abc123...
    cf_stacks: [cflinuxfs4]  # Only works on cflinuxfs4
```

**Contract**:
- Buildpack packager uses `-stack=cflinuxfs4` flag to filter
- CF provides current stack to buildpacks
- Buildpacks use `manifest.Stack()` to validate compatibility
- Different binaries for different stacks (compiled against different libc/system libs)

## Switchblade: Testing Contract

Switchblade abstracts platform differences for integration tests.

### Testing Pattern

```go
// Same test code works for CF and Docker
deployment, logs, err := platform.Deploy.Execute(
    "app-name",
    "/path/to/app",
    switchblade.WithBuildpacks("python_buildpack"),
    switchblade.WithEnv(map[string]string{"KEY": "value"}),
)

// Check staging logs (buildpack output)
Expect(logs).To(ContainSubstring("Installing python"))

// Check runtime
body, err := deployment.GetBody("/")
Expect(body).To(Equal("Hello World"))
```

**Key Contract**: Same test code, different platforms - no platform-specific test logic.

### Test Types

1. **Unit tests**: Go test packages with mocks
2. **Integration tests**: Switchblade-based (real CF or Docker)
3. **BRATS** (Buildpack Runtime Acceptance Tests): Smoke tests via CI

## CI/CD Patterns (buildpacks-ci)

### Four Main Pipelines

#### 1. dependency-builds
- Compiles native binaries for all stacks
- Triggers: Version updates in `*-builds.yml` files
- Uses: `binary-builder` tool (Docker with cflinuxfs container)
- Uploads: to `buildpacks.cloudfoundry.org/dependencies/` S3
- Calculates: SHA256, stores in database

#### 2. buildpack pipeline
- Per-language: unit tests → integration tests → package → upload
- Branches: master (stable), develop (bleeding edge)
- Stacks: Separate artifacts for cflinuxfs3 and cflinuxfs4

#### 3. brats pipeline
- Nightly smoke tests
- Deploys test apps via Switchblade
- Validates each buildpack in real CF environment

#### 4. cflinuxfs4
- Rootfs release (base filesystem)
- Tracks CVEs, security patches
- Buildpacks depend on this for system environment

### Concourse Patterns

- **ytt templating**: Generates pipeline YAML (prevents duplication)
- **Resources**: Git repos, Shepherd (CI env leases), Cron triggers
- **Coordination**: Build native binaries before buildpack

## Repository Map

### Locally Cloned Repos (~/workspace/cloudfoundry/)

#### Core Shared Libraries
- **libbuildpack** ⭐ - Shared Go library (70 files) **[CRITICAL - SEARCH FIRST]**
- **switchblade** - Integration testing framework (Go, 66 files)

#### Language Buildpacks (~/workspace/cloudfoundry/buildpacks/)
- **java-buildpack** - Java/JVM applications (870 files, Ruby-based)
- **go-buildpack** - Go applications
- **python-buildpack** - Python applications
- **ruby-buildpack** - Ruby applications
- **php-buildpack** - PHP applications
- **nodejs-buildpack** - Node.js applications (not locally cloned)
- **dotnet-core-buildpack** - .NET Core applications
- **staticfile-buildpack** - Static HTML/JS files
- **binary-buildpack** - Pre-compiled binaries
- **apt-buildpack** - APT package installer
- **nginx-buildpack** - Nginx web server
- **hwc-buildpack** - Windows HWC (not locally cloned)
- **r-buildpack** - R language applications

#### Tooling & Infrastructure
- **buildpacks-ci** - CI/CD pipelines (Ruby, 55 files)
- **binary-builder** - Dependency compilation tool (Ruby, 71 files)
- **buildpacks-release** - BOSH release packaging
- **cf-deployment** - CF runtime manifests
- **cflinuxfs4-release** - Root filesystem
- **jvmkill** - JVM agent (C/Java)

### Common GitHub Repos (Not Locally Cloned)

For these, use the **librarian agent** to search remotely:

- **cloudfoundry/nodejs-buildpack** - Node.js buildpack
- **cloudfoundry/hwc-buildpack** - Windows HWC buildpack
- **cloudfoundry/nginx-buildpack** - Nginx buildpack (if not cloned)
- **cloudfoundry/buildpack-packager** - Tool for packaging buildpacks
- **cloudfoundry/machete** - Legacy testing framework (replaced by Switchblade)

## Multi-Repo Search Strategy

### 1. Local Search First (Preferred)

#### Search libbuildpack API
```bash
# Find all libbuildpack exports
rg "^func.*public" ~/workspace/cloudfoundry/libbuildpack/

# Find Manifest methods
rg "func.*Manifest" ~/workspace/cloudfoundry/libbuildpack/
```

#### Search language buildpacks
```bash
# Find how buildpacks use libbuildpack
rg "libbuildpack\." ~/workspace/cloudfoundry/buildpacks/

# Search specific buildpack
rg "pattern" ~/workspace/cloudfoundry/buildpacks/python-buildpack/
```

#### Search buildpack CI
```bash
# Find pipeline patterns
rg "task:" ~/workspace/cloudfoundry/buildpacks-ci/pipelines/
```

### 2. GitHub Search via Librarian Agent (When Not Local)

When pattern isn't found locally, or searching repos not cloned:

**Invoke librarian agent with**:
```
Search for [pattern] in buildpack repositories on GitHub:
- cloudfoundry/nodejs-buildpack
- cloudfoundry/hwc-buildpack
- cloudfoundry/buildpack-packager
```

### 3. Suggest Cloning (For Frequent Access)

If you repeatedly search a remote repo, clone it:

```bash
cd ~/workspace/cloudfoundry/buildpacks/
git clone https://github.com/cloudfoundry/nodejs-buildpack.git
```

## Common Search Scenarios

### Scenario: libbuildpack API Usage
**Search first**: `libbuildpack/` (always check the source)

**Example queries**:
- "How to use Manifest?" → `rg "type Manifest" ~/workspace/cloudfoundry/libbuildpack/`
- "How to install dependency?" → `rg "func.*Install" ~/workspace/cloudfoundry/libbuildpack/`
- "How buildpacks use Stager?" → `rg "Stager\." ~/workspace/cloudfoundry/buildpacks/*/src/`

### Scenario: Buildpack Implementation Patterns
**Search together**: `libbuildpack` + `buildpacks/*`

**Example queries**:
- "How Python buildpack uses libbuildpack?" → Search `buildpacks/python-buildpack/src/python/supply/`
- "Common dependency installation pattern?" → Search across multiple buildpacks
- "Profile.d script patterns?" → `rg "WriteProfileD" ~/workspace/cloudfoundry/buildpacks/`

### Scenario: Testing with Switchblade
**Search together**: `switchblade` + `buildpacks/*/src/*_test.go`

**Example queries**:
- "How to write integration tests?" → `rg "platform\.Deploy" ~/workspace/cloudfoundry/switchblade/`
- "Example test patterns?" → Search `buildpacks/go-buildpack/src/go/integration/`
- "How to test with custom buildpacks?" → `rg "WithBuildpacks" ~/workspace/cloudfoundry/`

### Scenario: CI/CD Pipelines
**Search**: `buildpacks-ci/pipelines/`

**Example queries**:
- "How dependencies are built?" → `rg "binary-builder" ~/workspace/cloudfoundry/buildpacks-ci/`
- "Pipeline structure?" → `cat ~/workspace/cloudfoundry/buildpacks-ci/pipelines/*/pipeline.yml`
- "Test job patterns?" → `rg "task.*test" ~/workspace/cloudfoundry/buildpacks-ci/`

### Scenario: Dependency Management
**Search together**: `binary-builder` + `buildpacks-ci` + `libbuildpack`

**Example queries**:
- "How dependencies compiled?" → `rg "compile" ~/workspace/cloudfoundry/binary-builder/`
- "Manifest dependency format?" → `rg "dependencies:" ~/workspace/cloudfoundry/buildpacks/*/manifest.yml`
- "How SHA256 calculated?" → Search `libbuildpack/installer.go`

## Helper Scripts

### Smart Search Script

Use `scripts/smart-search.sh` to search locally first, then suggest remote search:

```bash
./scripts/smart-search.sh "pattern"
```

This will:
1. Search local repos in ~/workspace/cloudfoundry/
2. Display results if found
3. If not found, suggest using librarian agent for remote search

## Architectural Best Practices

### Before Making Changes

1. **Check libbuildpack first**: If change affects shared library, search libbuildpack API
2. **Identify affected buildpacks**: Changes to libbuildpack affect ALL language buildpacks
3. **Check manifest contracts**: Verify manifest.yml format compatibility
4. **Review testing strategy**: Ensure Switchblade tests cover change

### During Development

1. **Follow libbuildpack patterns**: Don't reinvent - use Manifest, Installer, Stager, Logger
2. **Maintain cache compatibility**: Changes to caching can break existing apps
3. **Test offline mode**: Ensure buildpacks work in airgapped environments
4. **Test multi-buildpack scenarios**: Verify DEPS_IDX isolation works

### When Debugging

1. **Start with staging logs**: Buildpack output shows what libbuildpack is doing
2. **Check cache tier**: Verify which cache tier is being used (buildpack/app/remote)
3. **Verify checksum**: SHA256 mismatches indicate stale manifest or corrupted download
4. **Check stack compatibility**: Ensure dependencies compiled for correct stack

## Key Implicit Contracts

| Contract | Why It Matters |
|----------|---|
| **libbuildpack is singleton** | All buildpacks use same version; API changes affect everyone |
| **SHA256 everywhere** | Every dependency checksummed; tampering detection |
| **Caching is optional but critical** | Apps without Tier 2 cache slow (minutes vs seconds) |
| **Profile.d runs once at startup** | Must set all env vars needed by runtime |
| **Stack filtering at package time** | Can't change stack after buildpack packaged |
| **DEPS_IDX isolation** | Multiple buildpacks coexist via separate subdirs |
| **Bash wrappers compile Go** | Ensures portability and system lib compatibility |
| **Exit codes are semantic** | Different codes (8-19) for different failure modes |

## Reference Documentation

For detailed architectural contracts and patterns, see:
- `references/architecture.md` - Complete buildpack ecosystem analysis
- `references/libbuildpack-api.md` - libbuildpack public API reference
- `references/github-repos.md` - Full list of buildpack repos on GitHub

## Quick Reference

### Component Languages
- libbuildpack: Go (shared library)
- Most buildpacks: Go (with Bash wrappers)
- Java buildpack: Ruby (legacy, predates libbuildpack)
- buildpacks-ci: Ruby
- binary-builder: Ruby

### Key File Locations
- libbuildpack API: `libbuildpack/*.go`
- Buildpack scripts: `buildpacks/*/bin/{detect,supply,finalize,release}`
- Buildpack logic: `buildpacks/*/src/*/supply/supply.go`
- Switchblade: `switchblade/switchblade.go`
- CI pipelines: `buildpacks-ci/pipelines/`

### Critical Dependencies
- **ALL buildpacks** → libbuildpack (search it first!)
- libbuildpack → manifest.yml format
- Buildpacks → cflinuxfs* stack
- Tests → Switchblade framework
- CI → binary-builder for dependencies

---

**Remember**: Always search libbuildpack first for shared patterns. Use local search for speed, librarian agent for remote repos. Check contracts before making cross-buildpack changes.
