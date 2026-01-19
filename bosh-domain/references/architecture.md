# BOSH Architecture: Detailed Contracts and Patterns

This document provides detailed architectural context for BOSH components, their interactions, and implicit contracts.

## Component Relationships

BOSH has a **star topology** with the Director at the center:

```
Director (Ruby) -- NATS Message Bus -- Agent (Go, one per VM)
    |                                      |
    +-- ExternalCPI (subprocess)          +-- Local filesystem/disk management
    |   (infrastructure provider)          +-- Package compilation
    |                                      +-- Release/job application
    +-- Database (Postgres)
    +-- Blobstore (S3/GCS/DAV)
```

**Key repos and their roles:**
- **bosh/**: Director release and common library (Ruby)
- **bosh-agent/**: Agent runs on each deployed VM (Go)
- **bosh-aws-cpi-release, bosh-google-cpi-release, etc.**: Infrastructure-specific CPI implementations
- **bosh-linux-stemcell-builder/**: Base OS image + agent bootstrap
- **bosh-deployment/**: Reference deployment manifests with configuration patterns

## Cross-Component Communication Contracts

### Director ↔ Agent (NATS Protocol)

**Transport**: NATS (custom fork supporting TLS + plaintext on same port)

**Communication pattern**: RPC-style request/response

**Agent Client Interface** (`agent_client_interface.go`): Defines 30+ methods
- `Ping()` - health check
- `Start()`, `Stop()`, `Drain()` - job lifecycle  
- `Apply(ApplySpec)` - apply release/job configs
- `GetState()` - retrieve agent status
- `CompilePackage()` - compile source packages
- `MountDisk()`, `UnmountDisk()` - disk management

**Key Contract**: 
- Agent must respond to all methods
- Timeout handling is Director's responsibility
- Agent heartbeat indicates health
- NATS message format is versioned implicitly via method stability

**File Locations**:
- Interface definition: `bosh-agent/agentclient/agent_client_interface.go`
- Apply spec: `bosh-agent/agentclient/applyspec/`
- Director implementation: `bosh/src/bosh-director/lib/bosh/director/agent_client.rb`

### Director ↔ CPI (External Process)

**Communication**: Subprocess (stdin/stdout JSON-RPC)

**CPI Configuration** (`cpi_config/cpi.rb`):
- Each CPI has `name`, `type`, `exec_path` (default: `/var/vcap/jobs/{type}_cpi/bin/cpi`)
- Optional `properties` for provider-specific config
- `migrated_from` list for CPI migration support

**Methods**: 
- `create_vm` - create new VM
- `delete_vm` - destroy VM
- `attach_disk`, `detach_disk` - disk management
- `snapshot_disk` - create disk snapshot
- `info` - return CPI capabilities and API version

**API Versioning**: 
- Director and CPI negotiate via `info()` method
- `preferred_cpi_api_version` in config
- Supports method aliasing for migration (old → new method names)

**Key Contracts**:
- CPI receives valid JSON input
- Must be idempotent for create/delete operations
- Must handle missing resources gracefully
- Must not assume VMs have persistent configuration across calls
- CPI crash doesn't crash Director (process isolation)

**File Locations**:
- CPI factory: `bosh/src/bosh-director/lib/bosh/director/cloud_factory.rb`
- CPI config: `bosh/src/bosh-director/lib/bosh/director/cpi_config/cpi.rb`
- Example CPIs: `bosh-aws-cpi-release/`, `bosh-google-cpi-release/`

### Stemcell ↔ Agent Bootstrap

**Contract**: Stemcell provides base OS + agent binary

**Integration Point**: Agent initialization script reads settings from:
- CDROM metadata (AWS, Google, Azure)
- Config drive (OpenStack, CloudStack)
- DHCP userdata fallback

**Settings Source Factory**: Determines metadata retrieval method per IaaS

**Key Contracts**:
- Settings are available at bootstrap (from metadata service)
- Agent can reach Director on NATS at configured address
- Local disk management tools (fdisk, lvm, etc.) are available
- Agent can execute arbitrary job start scripts
- Base OS is stable and deterministic

**File Locations**:
- Stemcell builder: `bosh-linux-stemcell-builder/stemcell_builder/`
- Agent bootstrap: `bosh-agent/platform/`
- Integration guide: `bosh-linux-stemcell-builder/AGENTS.md`

## Configuration Patterns

### Multi-layer Configuration Hierarchy

1. **Cloud Config** (`cloud_config.yml`) - VM sizes, networks, disk types, availability zones
2. **CPI Config** (`cpi_config.yml`) - Multiple CPIs, each with properties
3. **Deployment Manifest** - Release, job, instance group specs
4. **Runtime Config** - Addon releases applied to all deployments
5. **Config Server** - Dynamic variable interpolation

### CPI Config Example Pattern

```yaml
cpis:
- name: aws-primary
  type: aws
  properties: {...}
- name: aws-secondary
  type: aws
  properties: {...}
- name: gcp
  type: gcp
  migrated_from:
  - name: old-gcp-name
```

**Why Separate CPI Config**:
- Cloud config is deployment manifest (user data)
- CPI config is infrastructure provider setup (operator data)
- Allows multi-cloud deployments with different CPIs per AZ

## Data Flow Contracts

### Deployment → Agent Workflow

1. Director creates deployment plan (instance groups, jobs, packages)
2. Director calls CPI to create VMs (with stemcell)
3. Director waits for agent heartbeat on NATS
4. Director sends `apply(ApplySpec)` with:
   - Job templates (rendered configs)
   - Package binaries (compiled or from blobstore)
   - Network specs, DNS, persistent disk hints
5. Agent applies spec, starts jobs, reports back

### Package Compilation Flow

- Director detects missing compiled packages
- Calls CPI to create temporary compilation VMs
- Sends `compile_package(packageSource, dependencies)` to agent
- Agent downloads source, compiles, uploads back to blobstore
- Director uses compiled package for deployment

## Version and Compatibility Contracts

### Stemcell API Version

- Stemcell embeds agent binary with specific capabilities
- Agent announces API version on startup
- Director uses minimum of (stemcell_api_version, preferred_cpi_api_version)
- Allows forwards compatibility - newer directors can work with older stemcells

### CPI API Version

- CPI responds to `info()` call with `api_version`
- Director wraps CPI with `ExternalCpiResponseWrapper` for version negotiation
- Supports method aliasing for migration (e.g., old → new method names)

### Agent Protocol Stability

- `agentclient` Go package defines stable interface
- NATS message format is versioned implicitly via method stability
- Agent method names are the contract - changing breaks compatibility

## Release and Packaging Patterns

### Release Structure

- **Packages**: source code + compile spec (dependencies, compile script)
- **Jobs**: templates (config files), properties (schema), run scripts
- **Compiled packages**: stored in blobstore with SHA1 digest
- **Tracking**: Director tracks compiled_package_requirement relationships

### Artifact Versioning

- Releases have semantic versions (e.g., `v270.5.0`)
- Stemcells have format versions (e.g., `ubuntu-jammy-1.0`)
- CPI releases track compatibility via dependency constraints in manifests

## Implicit Contracts and Assumptions

### Director Assumptions

- Agent will respond to RPC calls within reasonable timeout
- Agent heartbeat indicates health
- CPI subprocess will complete operations and return JSON
- Blobstore is consistent and reliable
- Database is the single source of truth for state

### Agent Assumptions

- Settings are available at bootstrap (from metadata service)
- Can reach Director on NATS at configured address
- Local disk management tools (fdisk, lvm, etc.) are available
- Can execute arbitrary job start scripts

### CPI Assumptions

- Receives valid JSON input
- Must be idempotent for create/delete operations
- Must handle missing resources gracefully
- Must not assume VMs have persistent configuration across calls

### Stemcell Assumptions

- Base OS is stable
- Agent binary is compatible with IaaS metadata format
- Boot sequence is deterministic and fast

## Key Architectural Decisions

### Why External CPI Process?

- **Language agnostic** (Ruby, Go, etc.)
- **Isolation**: CPI crash doesn't crash Director
- **Simple contract**: JSON over stdout/stdin
- **Easy to test** independently

### Why NATS for Agent Communication?

- Pub/sub + request/reply patterns
- Low latency, good for many agents
- TLS support for security
- Custom fork handles simultaneous TLS/plaintext (Director cert transition safety)

### Why Separate Stemcell Builder?

- OS-specific (Ubuntu, Windows, etc.)
- IaaS-specific (metadata service integration)
- Decouples OS updates from BOSH releases
- Different release cadence

### Why CPI Config is Separate from Cloud Config?

- Cloud config is deployment manifest (user data)
- CPI config is infrastructure provider setup (operator data)
- Allows multi-cloud deployments with different CPIs per AZ

## Extension Points for Developers

- **Custom CPI**: Implement JSON-RPC interface, point to executable
- **Custom blobstore**: Create `bosh-blobstore-{name}` executable
- **Custom metadata source**: Extend agent's settings_source_factory
- **Custom cloud properties**: Any valid YAML in CPI/cloud config properties
- **Custom jobs/releases**: Follow templating and packaging conventions

## Common Debugging Patterns

### VM Creation Issues

1. Check Director logs for CPI calls
2. Verify CPI subprocess stdout/stderr
3. Check IaaS provider console for VM state
4. Verify cloud config (networks, VM types)

### Agent Communication Issues

1. Check NATS connectivity (Director → Agent)
2. Verify agent logs on VM (SSH or serial console)
3. Check agent heartbeat in Director logs
4. Verify metadata service accessibility from VM

### Deployment Failures

1. Check deployment plan in Director logs
2. Verify package compilation succeeded
3. Check job templates rendered correctly
4. Verify agent applied ApplySpec successfully

## Key File Locations Reference

### Director
- `bosh/src/bosh-director/lib/bosh/director/cloud_factory.rb` - CPI instantiation
- `bosh/src/bosh-director/lib/bosh/director/cpi_config/cpi.rb` - CPI config model
- `bosh/src/bosh-director/lib/bosh/director/deployment_plan/` - Deployment planning
- `bosh/src/bosh-director/lib/bosh/director/models/` - Domain models

### Agent
- `bosh-agent/agentclient/agent_client_interface.go` - Agent RPC interface
- `bosh-agent/agentclient/applyspec/` - Apply specification contracts
- `bosh-agent/platform/` - OS-specific implementations
- `bosh-agent/docs/dev_setup.md` - Development setup

### Stemcells
- `bosh-linux-stemcell-builder/AGENTS.md` - Agent integration guide
- `bosh-linux-stemcell-builder/stemcell_builder/` - Build scripts

### Deployments
- `bosh-deployment/` - Reference manifests for all infrastructures

---

**Remember**: These contracts are implicit - they're not always documented in code. Understanding them is critical for maintaining compatibility across BOSH components.
