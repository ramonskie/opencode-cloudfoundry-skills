# Cloud Foundry Buildpacks Architecture: Detailed Contracts

This document provides detailed architectural context for the CF buildpacks ecosystem.

## Ecosystem Architecture

```
CF Platform
    ↓ (calls scripts with positional args)
Language Buildpack (language-specific)
    ↓ (imports as Go library)
libbuildpack ⭐ (shared abstraction layer)
    ↓ (reads & resolves)
manifest.yml (dependency declarations)
    ↓ (downloads from)
buildpacks.cloudfoundry.org/dependencies/ (S3 bucket)
```

## libbuildpack: The Core Abstraction

### Purpose
lib

buildpack encapsulates common buildpack functionality so language buildpacks don't reimplement the same patterns.

### Four Core Components

#### 1. Manifest (`manifest.go`)
**Purpose**: Parse and manage `manifest.yml` dependency declarations

**Key Methods**:
- `NewManifest(dir, logger, time)` - Load and parse manifest.yml
- `DefaultVersion(depName)` - Resolve version constraints (e.g., "3.2.x" → "3.2.2")
- `AllDependencyVersions(depName)` - List all available versions
- `IsCached()` - Check if buildpack is in offline/cached mode
- `Stack()` - Return current stack (cflinuxfs3/cflinuxfs4/cflinuxfs5)

**Contract**:
- manifest.yml MUST exist in buildpack root
- Dependencies MUST have: name, version, uri, sha256, cf_stacks
- Version constraints support semver: `3.x`, `3.2.x`, `~>3.1`

#### 2. Installer (`installer.go`)
**Purpose**: Three-tier dependency resolution and installation

**Key Methods**:
- `NewInstaller(manifest)` - Create installer from manifest
- `SetAppCacheDir(dir)` - Enable Tier 2 caching (critical for performance)
- `InstallDependency(dep, targetDir)` - Install dependency to directory
- `InstallOnlyVersion(depName, targetDir)` - Install if exactly one version available
- `CleanupAppCache()` - Remove unused cached dependencies

**Three-Tier Resolution**:
1. **Buildpack cache** (offline mode): Copy from `dependencies/` in buildpack zip
2. **App cache** (persistent): Check `$CACHE_DIR/dependencies/`, keyed by SHA256
3. **Remote download**: Fetch from URI, verify SHA256, optionally cache

**Contract**:
- SHA256 MUST match or installation fails
- URIs MUST be accessible (or cached)
- Retries download failures automatically
- Cleans up partial downloads on error

#### 3. Stager (`stager.go`)
**Purpose**: Manage staging directories and environment configuration

**Key Methods**:
- `NewStager(args, logger, manifest)` - Parse CF-provided args
- `BuildDir()`, `CacheDir()`, `DepDir()` - Get staging directories
- `DepsIdx()` - Get buildpack index (for multi-buildpack isolation)
- `WriteEnvFile(name, value)` - Write env var for subsequent buildpacks
- `WriteProfileD(filename, content)` - Create app startup script
- `LinkDirectoryInDepDir(source, target)` - Create symlinks in deps directory

**Contract**:
- Args MUST be: [BUILD_DIR, CACHE_DIR, DEPS_DIR, DEPS_IDX, ...] (positional)
- DEPS_IDX isolates buildpack files in multi-buildpack scenarios
- Profile.d scripts run ONCE at app startup (not per request)
- Env files affect only subsequent buildpacks in chain

#### 4. Logger (`logger.go`)
**Purpose**: Structured, colored logging for buildpack output

**Key Methods**:
- `NewLogger(writer)` - Create logger
- `Debug(format, args...)` - Debug-level logging
- `Info(format, args...)` - Info-level logging
- `Warning(format, args...)` - Warning-level logging
- `Error(format, args...)` - Error-level logging

**Contract**:
- Output goes to stdout (CF captures for staging logs)
- Colored output for terminal readability
- Structured format for parsing

### Standard Initialization Pattern

Every buildpack using libbuildpack follows this exact pattern:

```go
func main() {
    // 1. Create logger
    logger := libbuildpack.NewLogger(os.Stdout)
    
    // 2. Load manifest from buildpack directory
    buildpackDir, err := libbuildpack.GetBuildpackDir()
    manifest, err := libbuildpack.NewManifest(buildpackDir, logger, time.Now())
    
    // 3. Create stager from CF-provided arguments
    stager := libbuildpack.NewStager(os.Args[1:], logger, manifest)
    
    // 4. Create installer and enable app caching
    installer := libbuildpack.NewInstaller(manifest)
    installer.SetAppCacheDir(stager.CacheDir())
    defer installer.CleanupAppCache()
    
    // 5. Install dependencies
    dep := libbuildpack.Dependency{Name: "python", Version: "3.11.0"}
    err = installer.InstallDependency(dep, "/tmp/python")
    
    // 6. Write environment configuration
    stager.WriteEnvFile("PYTHON_HOME", "/tmp/python")
    stager.WriteProfileD("python.sh", "export PATH=/tmp/python/bin:$PATH")
}
```

## Buildpack Lifecycle Detailed

### 1. Detect Phase

**Script**: `bin/detect <BUILD_DIR>`

**Purpose**: Determine if buildpack applies to the app

**Contract**:
- Exit 0 if buildpack applies, echo language name to stdout
- Exit non-zero if buildpack doesn't apply
- No files should be written
- Fast execution (< 1 second preferred)

**Example**:
```bash
#!/bin/bash
if [ -f "$1/requirements.txt" ]; then
  echo "Python"
  exit 0
fi
exit 1
```

### 2. Supply Phase

**Script**: `bin/supply <BUILD> <CACHE> <DEPS> <IDX>`

**Purpose**: Install buildpack dependencies

**Contract**:
- `$1` = BUILD_DIR (app source code)
- `$2` = CACHE_DIR (persistent cache between stagings)
- `$3` = DEPS_DIR (shared across all buildpacks)
- `$4` = DEPS_IDX (integer, this buildpack's subdirectory index)
- Install dependencies to `$3/$4/` to isolate from other buildpacks
- Use `$2` for caching downloaded dependencies
- Exit 0 on success, non-zero on failure

**Common Pattern** (Bash wrapper → Go binary):
```bash
#!/bin/bash
set -euo pipefail
export GOPATH=$HOME/go
cd $(dirname $0)/..
go build -o /tmp/supply ./src/python/supply/cli
/tmp/supply "$@"
```

### 3. Finalize Phase

**Script**: `bin/finalize <BUILD> <CACHE> <DEPS> <IDX> <PROFILE_DIR>`

**Purpose**: Final configuration before app runs

**Contract**:
- Same as supply, plus `$5` = PROFILE_DIR (startup script directory)
- Write scripts to `$5/*.sh` that run at app startup
- Set PATH, environment variables for runtime
- Exit 0 on success

**Profile.d Contract**:
- Scripts run ONCE at container startup (not per HTTP request)
- Must be idempotent (may run multiple times during restarts)
- Output not shown to user
- Use for: setting PATH, runtime env vars, one-time initialization

### 4. Release Phase

**Script**: `bin/release <BUILD_DIR>`

**Purpose**: Return YAML with runtime configuration

**Contract**:
- Echo YAML to stdout
- Specify `default_process_types` (commands to run app)
- Specify `config_vars` (optional environment variables)
- Exit 0 always (non-zero indicates error)

**Example**:
```yaml
default_process_types:
  web: python app.py
config_vars:
  PYTHON_VERSION: 3.11.0
```

## Multi-Buildpack Communication Protocol

When multiple buildpacks are used together (multi-buildpack staging), they communicate via a directory-based protocol.

### Supply/Finalize Pattern

**Supply Phase** (buildpacks 0 to N-1):
- Runs for ALL buildpacks in the chain
- Installs dependencies to `$DEPS_DIR/$DEPS_IDX/`
- Writes `config.yml` for communication with final buildpack
- Non-destructive (doesn't modify app directory)
- Each buildpack isolated via unique $DEPS_IDX

**Finalize Phase** (buildpack N only):
- Runs ONLY for the last buildpack in chain
- Reads from ALL `$DEPS_DIR/*/config.yml` files
- Integrates all buildpack contributions
- Modifies app directory for launch
- Writes final startup configuration

### Directory Structure

```
/tmp/
├── app/              # Application source code
├── cache/            # Persistent cache between stagings
└── deps/             # Multi-buildpack dependencies
    ├── 0/            # First buildpack contributions ($DEPS_IDX=0)
    │   ├── config.yml       # Configuration for final buildpack
    │   ├── bin/             # Binaries to add to $PATH
    │   ├── lib/             # Libraries for $LD_LIBRARY_PATH
    │   ├── include/         # Headers for compilation
    │   └── env/             # Environment variables
    ├── 1/            # Second buildpack contributions ($DEPS_IDX=1)
    │   └── config.yml
    ├── 2/            # Third buildpack contributions ($DEPS_IDX=2)
    │   └── config.yml
    └── ...
```

### config.yml Contract

Each buildpack in supply phase can write `$DEPS_DIR/$DEPS_IDX/config.yml` to communicate with the final buildpack.

**Example** (from Java ecosystem):
```yaml
# $DEPS_DIR/0/config.yml (JRE buildpack)
name: openjdk
container: play
environment_variables:
  JAVA_HOME: /tmp/deps/0
java_opts:
  - -Xmx512m
  - -Xms256m
```

**Contract**:
- Schema is buildpack-specific (no universal standard)
- Final buildpack MUST document expected config.yml format
- Config files are additive (final buildpack merges all)
- Missing config.yml is valid (optional communication)

### Integration Pattern (Final Buildpack)

How the final buildpack reads previous buildpacks' contributions:

```go
// Get deps directory root
depsDir := stager.DepsDir()        // e.g., /tmp/deps/
currentIdx := stager.DepsIdx()     // e.g., 2 (this is buildpack #2)

// Iterate through all previous buildpacks
for idx := 0; idx < currentIdx; idx++ {
    configPath := filepath.Join(depsDir, strconv.Itoa(idx), "config.yml")
    
    // Check if config exists
    if _, err := os.Stat(configPath); os.IsNotExist(err) {
        continue  // Skip if no config provided
    }
    
    // Read and parse config
    data, _ := ioutil.ReadFile(configPath)
    var config SupplyConfig
    yaml.Unmarshal(data, &config)
    
    // Integrate into final buildpack behavior
    // E.g., add to PATH, set env vars, configure runtime
}
```

### $DEPS_DIR/$DEPS_IDX Isolation

Each buildpack gets its own isolated subdirectory:

```bash
# Buildpack 0 (JRE supply)
DEPS_DIR=/tmp/deps
DEPS_IDX=0
# Installs to: /tmp/deps/0/

# Buildpack 1 (dependency supply)
DEPS_DIR=/tmp/deps
DEPS_IDX=1
# Installs to: /tmp/deps/1/

# Buildpack 2 (app buildpack finalize)
DEPS_DIR=/tmp/deps
DEPS_IDX=2
# Reads from: /tmp/deps/0/, /tmp/deps/1/
# Installs to: /tmp/deps/2/
```

**Why Isolation Matters**:
- Prevents file conflicts between buildpacks
- Each buildpack can use common directory names (bin/, lib/)
- Final buildpack can iterate numerically (0, 1, 2, ...)
- Enables composable buildpack architecture

### Real-World Example: Java Multi-Buildpack

**Scenario**: Deploy Java app with custom JRE

**Buildpack Chain**:
1. `java-jre-buildpack` (supply) - Installs OpenJDK
2. `java-app-buildpack` (finalize) - Compiles app, reads JRE config

**Supply Phase** (java-jre-buildpack):
```bash
# Called as: bin/supply /tmp/app /tmp/cache /tmp/deps 0
# Installs JRE to /tmp/deps/0/
# Writes config:
cat > /tmp/deps/0/config.yml <<EOF
name: openjdk
version: 17.0.5
java_home: /tmp/deps/0
EOF
```

**Finalize Phase** (java-app-buildpack):
```bash
# Called as: bin/finalize /tmp/app /tmp/cache /tmp/deps 1
# Reads /tmp/deps/0/config.yml
# Sets JAVA_HOME from config
# Compiles app using JRE from /tmp/deps/0/
# Writes startup script using JAVA_HOME
```

### libbuildpack Pattern

Modern buildpacks using libbuildpack (all Go-based buildpacks including java-buildpack after feature/go-migration):
- Use `stager.DepDir()` and `stager.DepsDir()` methods
- Automatic $DEPS_IDX parsing from args
- Follows CF multi-buildpack spec exactly
- Example: go-buildpack, python-buildpack, php-buildpack, java-buildpack

**Standard pattern**:
```go
// In supply or finalize
stager := libbuildpack.NewStager(os.Args[1:], logger, manifest)

// Get this buildpack's isolated directory
myDepDir := stager.DepDir()  // Returns /tmp/deps/$DEPS_IDX/

// Get parent deps directory for iteration
allDepsDir := stager.DepsDir()  // Returns /tmp/deps/

// Get this buildpack's index
myIdx := stager.DepsIdx()  // Returns integer like 0, 1, 2
```

### Testing Multi-Buildpack Scenarios

Using Switchblade:

```go
deployment, logs, err := platform.Deploy.Execute(
    "multi-buildpack-test",
    "./fixtures/java_app",
    switchblade.WithBuildpacks(
        "https://github.com/cloudfoundry/jre-buildpack",   // Supply
        "https://github.com/cloudfoundry/java-buildpack",  // Finalize
    ),
)

// Verify supply buildpack ran
assert.Contains(string(logs), "Installing JRE")

// Verify finalize buildpack integrated JRE
assert.Contains(string(logs), "Using JRE from /tmp/deps/0")
```

### Common Patterns

**Pattern 1: Language Runtime Supply**
- Supply buildpack installs runtime (Python, Ruby, Node.js)
- Finalize buildpack installs app dependencies using that runtime
- Enables swapping runtime versions without changing app buildpack

**Pattern 2: Native Library Supply**
- Supply buildpack installs system libraries (libpq, imagemagick)
- Finalize buildpack links app against those libraries
- Enables reusing compiled libraries across apps

**Pattern 3: Multi-Language Apps**
- Supply: Node.js buildpack (frontend build tools)
- Supply: Python buildpack (backend runtime)
- Finalize: App buildpack (integrates both)

### Debugging Multi-Buildpack Issues

**Check $DEPS_DIR structure**:
```bash
# In staging logs, look for:
ls -la /tmp/deps/
# Should show: 0/ 1/ 2/ (one per buildpack)
```

**Verify config.yml written**:
```bash
cat /tmp/deps/0/config.yml
# Should contain valid YAML
```

**Check final buildpack reads config**:
```bash
# In finalize logs, look for:
Reading configuration from /tmp/deps/0/config.yml
```

**Common Issues**:
- Config.yml schema mismatch (final buildpack expects different format)
- Missing config.yml (supply buildpack didn't write it)
- File permissions (config.yml not readable)
- $DEPS_IDX confusion (hardcoded paths instead of using $DEPS_IDX)

## Three-Tier Caching Strategy Detailed

### Tier 1: Buildpack Cache (Offline Mode)

**Location**: `dependencies/` directory in buildpack zip

**Created By**:
```bash
buildpack-packager build -cached=true
```

**Manifest Format**:
```yaml
dependencies:
  - name: ruby
    version: 3.2.2
    file: dependencies/ruby_3.2.2.tgz  # Local file path
    sha256: abc123...
    cf_stacks: [cflinuxfs4]
```

**When Used**:
- Airgapped/offline environments
- When `manifest.IsCached()` returns true
- No network access needed

**Contract**:
- Files MUST exist in `dependencies/` directory
- SHA256 MUST match file contents
- Stack filtering happens at package time

### Tier 2: App Cache (Persistent Between Stagings) ⭐ CRITICAL

**Location**: `$CACHE_DIR/dependencies/` (CF's persistent cache)

**Enabled By**:
```go
installer.SetAppCacheDir(stager.CacheDir())
```

**Keyed By**: SHA256 hash of dependency URI

**Lifecycle**:
- Survives app restages
- Shared across all apps using same buildpack + dependency
- Cleaned via `installer.CleanupAppCache()` (removes unused files)

**Performance Impact**:
- **Without Tier 2**: Re-download 100MB+ on every staging (2-5 minutes)
- **With Tier 2**: Copy from cache (5-10 seconds)

**Contract**:
- Must call `SetAppCacheDir()` to enable
- Must call `CleanupAppCache()` in defer to prevent cache bloat
- CF manages cache size and eviction

### Tier 3: Remote Download

**Location**: Direct fetch from `manifest.yml` URI

**When Used**:
- Dependency not in Tier 1 or Tier 2
- First time staging with this dependency

**Contract**:
- URI MUST be accessible
- SHA256 MUST match downloaded file
- Retries download on transient failures
- Can optionally cache in Tier 2 (if `SetAppCacheDir()` called)

### Resolution Flow

```
1. Check manifest.IsCached():
   YES → Copy from dependencies/ (Tier 1)
   NO → Continue to step 2

2. Check app cache ($CACHE_DIR/dependencies/):
   EXISTS → Copy from cache (Tier 2)
   NOT EXISTS → Continue to step 3

3. Download from URI (Tier 3):
   - Fetch from manifest.yml URI
   - Verify SHA256
   - If SetAppCacheDir() called, save to cache
   - Copy to target directory
```

## Stack Filtering Contract

### Purpose
Different stacks (cflinuxfs3, cflinuxfs4, cflinuxfs5) require different compiled binaries due to different system libraries (libc versions, etc.).

**Stack Lifecycle**:
- **cflinuxfs3**: DEPRECATED - Being removed from buildpacks
- **cflinuxfs4**: CURRENT - Production stack in active use
- **cflinuxfs5**: UPCOMING - In development for future releases

### Manifest Format

```yaml
dependencies:
  - name: ruby
    version: 3.2.2
    uri: https://buildpacks.cloudfoundry.org/dependencies/ruby/ruby_3.2.2_cflinuxfs4.tgz
    sha256: abc123...
    cf_stacks: [cflinuxfs4]  # Stack compatibility (cflinuxfs3 deprecated, cflinuxfs4 current, cflinuxfs5 upcoming)
```

### Buildpack Packager Filtering

```bash
buildpack-packager build -stack=cflinuxfs4
```

**Effect**:
- Includes ONLY dependencies with `cflinuxfs4` in `cf_stacks`
- Removes `cf_stacks` field from resulting manifest.yml (optimization)
- Creates stack-specific buildpack zip

### Runtime Stack Validation

```go
// Buildpack checks current stack
currentStack := manifest.Stack()
if currentStack != "cflinuxfs4" {
    return errors.New("incompatible stack")
}
```

**Contract**:
- CF provides stack to buildpack via environment variable
- Buildpack MUST verify stack compatibility
- Different stacks = different buildpack artifacts

## Switchblade Testing Contract

### Purpose
Abstract platform differences (CF vs Docker) for integration tests.

### Platform Interface

```go
type Platform interface {
    Deploy Deployer
}

type Deployer interface {
    Execute(name, appPath string, opts ...DeployOption) (Deployment, []byte, error)
}

type Deployment interface {
    GetBody(path string) (string, error)
    RuntimeLogs() string
    Destroy() error
}
```

### Usage Pattern

```go
func TestPythonBuildpack(t *testing.T) {
    // Works on both CF and Docker
    deployment, logs, err := platform.Deploy.Execute(
        "test-app",
        "./fixtures/simple_app",
        switchblade.WithBuildpacks("python_buildpack"),
        switchblade.WithEnv(map[string]string{"PYTHON_VERSION": "3.11"}),
    )
    defer deployment.Destroy()
    
    // Assert on staging logs (buildpack output)
    assert.Contains(t, string(logs), "Installing Python 3.11")
    
    // Assert on runtime behavior
    body, err := deployment.GetBody("/")
    assert.Equal(t, "Hello World", body)
}
```

### Deploy Options

- `WithBuildpacks(...string)` - Specify buildpacks in order
- `WithEnv(map[string]string)` - Set environment variables
- `WithServices(...Service)` - Bind services
- `WithoutInternetAccess()` - Test offline mode
- `WithStack(string)` - Specify stack (cflinuxfs4 current, cflinuxfs5 upcoming, cflinuxfs3 deprecated)

**Contract**:
- Same test code works on CF and Docker (no platform-specific logic)
- Staging logs = buildpack output (detect/supply/finalize)
- Runtime logs = app stdout/stderr
- Test failures clean up deployments automatically

## CI/CD Pipeline Contracts

### Dependency Build Pipeline

**Trigger**: Version updates in `*-builds.yml`

**Flow**:
1. Pull Docker image for stack (cflinuxfs4)
2. Run `binary-builder` with build recipe
3. Compile dependency inside container
4. Calculate SHA256 of compiled artifact
5. Upload to S3: `buildpacks.cloudfoundry.org/dependencies/{name}/{name}_{version}_{stack}.tgz`
6. Update buildpack manifests with new URI + SHA256

**Contract**:
- Binaries MUST be compiled in stack container (ensures libc compatibility)
- SHA256 MUST be calculated and stored
- Manifest updates MUST include SHA256

### Buildpack Build Pipeline

**Trigger**: Git push to master/develop

**Flow**:
1. Run unit tests (`scripts/unit.sh`)
2. Run integration tests (`scripts/integration.sh` with Switchblade)
3. Package buildpack (`buildpack-packager build`)
4. Upload to CF deployment
5. Run BRATS (smoke tests)
6. Tag release (master only)

**Contract**:
- All tests MUST pass before packaging
- Integration tests run on real CF or Docker
- Both cached and uncached buildpacks tested

---

**Key Takeaway**: libbuildpack provides a stable contract that all language buildpacks depend on. Understanding its four components (Manifest, Installer, Stager, Logger) is essential for buildpack development.
