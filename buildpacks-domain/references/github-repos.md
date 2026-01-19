# Cloud Foundry Buildpacks Repositories on GitHub

This document lists all buildpack-related repositories, organized by category.

## Locally Cloned Repos (~/workspace/cloudfoundry/)

### Core Shared Library ⭐ SEARCH FIRST
- **libbuildpack** - Shared Go library (70 files)
  - Location: `~/workspace/cloudfoundry/libbuildpack`
  - Purpose: Manifest, Installer, Stager, Logger for all buildpacks
  - Language: Go
  - **Critical**: ALL language buildpacks depend on this

### Language Buildpacks (~/workspace/cloudfoundry/buildpacks/)
- **java-buildpack** - Java/JVM applications (Go-based via feature/go-migration branch)
- **go-buildpack** - Go applications
- **python-buildpack** - Python applications
- **ruby-buildpack** - Ruby applications
- **php-buildpack** - PHP applications
- **dotnet-core-buildpack** - .NET Core applications
- **staticfile-buildpack** - Static HTML/JS files
- **binary-buildpack** - Pre-compiled binaries
- **apt-buildpack** - APT package installer
- **nginx-buildpack** - Nginx web server
- **r-buildpack** - R language

### Testing & Tooling
- **switchblade** - Integration testing framework (Go, 66 files)
- **buildpacks-ci** - CI/CD pipelines (Ruby, 55 files)
- **binary-builder** - Dependency compilation (Ruby, 71 files)
- **buildpacks-release** - BOSH release packaging

### Infrastructure
- **cf-deployment** - CF runtime manifests
- **cflinuxfs4-release** - Root filesystem (current production stack)
- **cflinuxfs5-release** - Root filesystem (upcoming stack)
- **jvmkill** - JVM agent (C/Java)

**Note**: cflinuxfs3 is deprecated and being removed from buildpacks.

## GitHub Repos (Not Locally Cloned)

Use **librarian agent** to search these remotely.

### Additional Language Buildpacks
- **cloudfoundry/nodejs-buildpack** - Node.js applications
  - Use for: Node.js patterns, npm/yarn integration
  - Language: Go

- **cloudfoundry/hwc-buildpack** - Windows HWC (Hostable Web Core)
  - Use for: Windows-specific buildpack patterns
  - Language: Go

### Tooling
- **cloudfoundry/buildpack-packager** - Packaging tool
  - Use for: Understanding buildpack packaging process
  - Language: Go
  - Purpose: Creates cached/uncached buildpack artifacts

- **cloudfoundry/compile-extensions** - Legacy buildpack utilities
  - Use for: Historical context (largely replaced by libbuildpack)
  - Language: Bash/Ruby

- **cloudfoundry/machete** - Legacy testing framework
  - Use for: Historical context (replaced by Switchblade)
  - Language: Ruby

### Deprecated/Legacy
- **cloudfoundry-community/multi-buildpack** - Run multiple buildpacks (deprecated in favor of built-in multi-buildpack support)

## Search Strategy by Use Case

### Finding libbuildpack Patterns ⭐ START HERE

**Local**: ~/workspace/cloudfoundry/libbuildpack/
```bash
# Find all public APIs
rg "^func \(" ~/workspace/cloudfoundry/libbuildpack/ | grep -v "_test.go"

# Find Manifest methods
rg "func.*Manifest\)" ~/workspace/cloudfoundry/libbuildpack/manifest.go

# Find Installer methods
rg "func.*Installer\)" ~/workspace/cloudfoundry/libbuildpack/installer.go
```

**Why search first**: ALL buildpacks import libbuildpack. Understanding the API is critical.

### Finding Language Buildpack Patterns

**Local**: ~/workspace/cloudfoundry/buildpacks/

```bash
# Find how buildpacks use libbuildpack
rg "libbuildpack\." ~/workspace/cloudfoundry/buildpacks/

# Find supply script patterns
find ~/workspace/cloudfoundry/buildpacks/ -name "supply.go" -exec cat {} \;

# Find manifest patterns
find ~/workspace/cloudfoundry/buildpacks/ -name "manifest.yml" -exec head -20 {} \;
```

**Remote** (nodejs, hwc):
```
Use librarian agent to search:
- cloudfoundry/nodejs-buildpack
- cloudfoundry/hwc-buildpack
```

### Finding Testing Patterns

**Local**: ~/workspace/cloudfoundry/switchblade/

```bash
# Find Switchblade API
rg "func.*Deploy" ~/workspace/cloudfoundry/switchblade/

# Find example tests
rg "platform\.Deploy\.Execute" ~/workspace/cloudfoundry/buildpacks/*/src/*/integration/
```

**When to search**:
- Writing new integration tests
- Understanding platform abstraction
- Debugging test failures

### Finding CI/CD Patterns

**Local**: ~/workspace/cloudfoundry/buildpacks-ci/

```bash
# Find pipeline structure
ls ~/workspace/cloudfoundry/buildpacks-ci/pipelines/

# Find task patterns
rg "task:" ~/workspace/cloudfoundry/buildpacks-ci/pipelines/*.yml

# Find binary build recipes
ls ~/workspace/cloudfoundry/buildpacks-ci/tasks/build-binary-new/
```

**When to search**:
- Understanding dependency build process
- Debugging pipeline failures
- Adding new buildpack to CI

### Finding Dependency Build Patterns

**Local**: ~/workspace/cloudfoundry/binary-builder/

```bash
# Find build recipes
ls ~/workspace/cloudfoundry/binary-builder/recipe/

# Find how dependencies compiled
rg "compile" ~/workspace/cloudfoundry/binary-builder/
```

**When to search**:
- Adding new dependency
- Debugging compilation issues
- Understanding stack compatibility

## Cloning Additional Repos

If you frequently search a remote repo, clone it:

```bash
# Node.js buildpack
cd ~/workspace/cloudfoundry/buildpacks/
git clone https://github.com/cloudfoundry/nodejs-buildpack.git

# Buildpack packager tool
cd ~/workspace/cloudfoundry/
git clone https://github.com/cloudfoundry/buildpack-packager.git
```

**Recommend cloning if**:
- You search it more than 3 times per week
- You're actively developing/debugging that component
- You need to make changes or submit PRs

## GitHub Organizations

Buildpacks are primarily in:
- **cloudfoundry/** - Official Cloud Foundry organization
- **cloudfoundry-community/** - Community-maintained buildpacks

## Useful GitHub Search Queries

When using librarian agent:

```
# Find libbuildpack usage across all buildpacks
org:cloudfoundry "libbuildpack." path:src/ language:go

# Find buildpack supply scripts
org:cloudfoundry filename:supply.go path:src/

# Find manifest examples
org:cloudfoundry filename:manifest.yml path:*/

# Find Switchblade usage
org:cloudfoundry "platform.Deploy.Execute" language:go

# Find CI pipeline patterns
org:cloudfoundry "buildpack" path:pipelines/ filename:*.yml
```

## Related Non-Buildpack Repos

These repos are related but not buildpacks:

- **cloudfoundry/cf-deployment** - CF runtime manifests (uses buildpacks)
- **cloudfoundry/cflinuxfs4** - Rootfs (current production stack)
- **cloudfoundry/cflinuxfs5** - Rootfs (upcoming stack)
- **cloudfoundry/diego-release** - Container runtime (executes staged apps)
- **cloudfoundry/garden-runc-release** - Low-level container runtime

**Note**: cflinuxfs3 is deprecated and no longer maintained.

---

**Tip**: When searching for buildpack patterns, ALWAYS check libbuildpack first. It's the source of truth for all shared behavior.
