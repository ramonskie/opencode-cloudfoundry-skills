---
name: bosh-domain
description: This skill should be used when working in BOSH repositories (bosh, bosh-agent, bosh-*-cpi-release, bosh-linux-stemcell-builder, bosh-bootloader, bosh-deployment, bosh-apt-resources) to provide architectural context about BOSH components, their communication contracts, cross-repository relationships, and multi-repo search strategies for local and remote code.
---

# BOSH Domain Knowledge

## When to Use This Skill

Use this skill when:
- Working in any BOSH-related repository in ~/workspace/bosh/
- Making changes that affect cross-component contracts (Director↔Agent, Director↔CPI, Stemcell↔Agent)
- Debugging issues involving BOSH component communication
- Understanding how BOSH components interact and depend on each other
- Searching for BOSH code across multiple repositories
- Needing to understand BOSH architectural patterns and conventions

## Architecture Overview

BOSH uses a **star topology** with the Director at the center:

```
User/Operator
    ↓ (HTTP/HTTPS API)
BOSH CLI (Go client)
    ↓ (HTTP/HTTPS)
Director (Ruby) -- NATS Message Bus -- Agent (Go, one per VM)
    |                                      |
    +-- ExternalCPI (subprocess)          +-- Local filesystem/disk management
    |   (infrastructure provider)          +-- Package compilation
    |                                      +-- Release/job application
    +-- Database (Postgres)
    +-- Blobstore (S3/GCS/DAV)
```

### Key Components

- **BOSH CLI** (bosh-cli/): Command-line client for interacting with Director (Go, v7.9.15+ installed)
- **Director** (bosh/): Orchestration engine written in Ruby, manages deployments
- **Agent** (bosh-agent/): Runs on each VM, executes director commands, written in Go
- **CPI** (bosh-*-cpi-release/): Cloud Provider Interface, infrastructure-specific plugins
- **Stemcells** (bosh-linux-stemcell-builder/): Base OS images with embedded agent
- **Bootloader** (bosh-bootloader/): Bootstrap tool to deploy BOSH itself
- **Deployment Manifests** (bosh-deployment/): Reference configurations for various infrastructures

## BOSH CLI (v2+)

The BOSH CLI is the primary interface for operators and developers to interact with the BOSH Director.

### Architecture

```
User → BOSH CLI (Go binary) → HTTP/HTTPS → Director API → NATS → Agents
                    ↓
                Config Files
                (~/.bosh/config)
```

### Installation & Configuration

**Installed Version**: v7.9.15 (check with `bosh --version`)

**Configuration Locations**:
- `~/.bosh/config` - CLI configuration (environments, credentials)
- Environment variables: `BOSH_ENVIRONMENT`, `BOSH_CLIENT`, `BOSH_CLIENT_SECRET`, `BOSH_DEPLOYMENT`

**Common Setup**:
```bash
# Alias an environment
bosh alias-env my-env -e 10.0.0.6 --ca-cert <(bosh int creds.yml --path /director_ssl/ca)

# Log in
bosh -e my-env log-in

# Set deployment context
export BOSH_ENVIRONMENT=my-env
export BOSH_DEPLOYMENT=my-deployment
```

### Command Categories

#### **Deployment Management** (Most Common)
- `bosh deploy` (`d`) - Deploy or update deployment
- `bosh delete-deployment` (`deld`) - Delete deployment
- `bosh vms` - List all VMs across deployments
- `bosh instances` (`is`) - List instances in current deployment
- `bosh ssh` - SSH into instances
- `bosh scp` - SCP files to/from instances
- `bosh logs` - Fetch logs from instances
- `bosh manifest` (`man`) - Show deployment manifest

#### **Release Management**
- `bosh releases` (`rs`) - List uploaded releases
- `bosh upload-release` (`ur`) - Upload release to Director
- `bosh create-release` (`cr`) - Create dev/final release
- `bosh finalize-release` - Create final release from dev tarball
- `bosh export-release` - Export compiled release
- `bosh delete-release` (`delr`) - Delete release from Director
- `bosh inspect-release` - Show release contents (jobs, packages)

#### **Stemcell Management**
- `bosh stemcells` (`ss`) - List uploaded stemcells
- `bosh upload-stemcell` (`us`) - Upload stemcell to Director
- `bosh delete-stemcell` (`dels`) - Delete stemcell from Director
- `bosh repack-stemcell` - Repack stemcell with custom content

#### **Instance Lifecycle**
- `bosh start` - Start stopped instances
- `bosh stop` - Stop instances (keeps VMs)
- `bosh restart` - Restart job processes
- `bosh recreate` - Recreate VMs (destroy + create)
- `bosh run-errand` - Execute errand job

#### **Debugging & Troubleshooting**
- `bosh tasks` (`ts`) - List running/recent tasks
- `bosh task` (`t`) - Track task output
- `bosh events` - Show audit events
- `bosh cloud-check` (`cck`) - Cloud consistency check
- `bosh locks` - Show active locks
- `bosh curl` - Make HTTP request to Director API
- `bosh pcap` - Capture network packets on instance

#### **Configuration Management**
- `bosh cloud-config` (`cc`) - Show cloud config
- `bosh update-cloud-config` (`ucc`) - Update cloud config
- `bosh runtime-config` (`rc`) - Show runtime config
- `bosh update-runtime-config` (`urc`) - Update runtime config
- `bosh cpi-config` - Show CPI config
- `bosh configs` (`cs`) - List all configs

#### **Environment Bootstrap** (Direct BOSH without Director)
- `bosh create-env` - Create/update standalone BOSH (bootstrap)
- `bosh delete-env` - Delete standalone BOSH
- `bosh start-env` - Start stopped BOSH environment
- `bosh stop-env` - Stop BOSH environment

#### **Release Development**
- `bosh init-release` - Initialize new release
- `bosh generate-job` - Create job skeleton
- `bosh generate-package` - Create package skeleton
- `bosh add-blob` - Add blob to release
- `bosh sync-blobs` - Download blobs from blobstore
- `bosh upload-blobs` - Upload blobs to blobstore
- `bosh vendor-package` - Vendor external package

### Key Flags

**Environment Selection**:
- `-e, --environment` - Target Director (or `$BOSH_ENVIRONMENT`)
- `-d, --deployment` - Target deployment (or `$BOSH_DEPLOYMENT`)

**Authentication**:
- `--client` - Username or UAA client (or `$BOSH_CLIENT`)
- `--client-secret` - Password or UAA secret (or `$BOSH_CLIENT_SECRET`)
- `--ca-cert` - Director CA certificate (or `$BOSH_CA_CERT`)

**Output Control**:
- `--json` - Output as JSON (for scripting)
- `--column` - Filter output columns
- `--no-color` - Disable colored output
- `-n, --non-interactive` - Don't prompt for input

**Deployment Options** (for `bosh deploy`):
- `--vars-file` (`-l`) - Load variables from YAML file
- `--var` (`-v`) - Set variable (key=value)
- `--ops-file` (`-o`) - Apply ops file to manifest
- `--recreate` - Recreate all VMs
- `--fix` - Recover deployment from partial state
- `--skip-drain` - Skip drain scripts (dangerous)
- `--canaries` - Override canary count
- `--max-in-flight` - Override max parallel operations

### Common Workflows

#### **Deploy a Release**
```bash
# 1. Upload stemcell and release
bosh upload-stemcell ~/stemcells/bosh-stemcell-1.234-aws-xen-hvm-ubuntu-jammy-go_agent.tgz
bosh upload-release ~/releases/my-release-1.0.0.tgz

# 2. Deploy
bosh -d my-deployment deploy manifest.yml \
  -l vars.yml \
  -o ops/custom.yml \
  -v version=1.0.0

# 3. Check deployment
bosh -d my-deployment vms
bosh -d my-deployment instances
```

#### **Debug Failing Deployment**
```bash
# 1. Check task output
bosh tasks --recent=10
bosh task 1234  # Follow specific task

# 2. SSH to failing instance
bosh -d my-deployment ssh my-vm/0

# 3. Check logs
bosh -d my-deployment logs my-vm/0

# 4. Run cloud-check
bosh -d my-deployment cloud-check --auto
```

#### **Create Development Release**
```bash
# In release directory
bosh create-release --force --timestamp-version
bosh upload-release
bosh -d test-deployment deploy manifest.yml
```

#### **Bootstrap BOSH Director**
```bash
# Using bosh-deployment manifests
bosh create-env bosh-deployment/bosh.yml \
  -o bosh-deployment/aws/cpi.yml \
  --vars-store ./creds.yml \
  --state ./state.json \
  -v access_key_id=... \
  -v secret_access_key=...
```

### CLI ↔ Director Contract

**Authentication Flow**:
1. CLI reads config from `~/.bosh/config` or env vars
2. Sends HTTP request to Director API with basic auth or UAA token
3. Director validates credentials via UAA or local user database
4. Director returns session token for subsequent requests

**Task Execution Flow**:
1. CLI sends deployment/action request to Director
2. Director creates task and returns task ID immediately
3. CLI polls task status via `/tasks/{id}` endpoint
4. CLI streams task output in real-time
5. Task completes with success/error state

**Manifest Processing**:
1. CLI interpolates variables (`--var`, `--vars-file`)
2. CLI applies ops files (`--ops-file`) sequentially
3. CLI sends final manifest to Director via HTTP POST
4. Director validates manifest schema
5. Director creates deployment plan and executes

### Common Use Cases

**For Operators**:
- Deploy/update production systems: `bosh deploy`
- Monitor deployments: `bosh vms`, `bosh instances`
- Troubleshoot issues: `bosh ssh`, `bosh logs`, `bosh cloud-check`
- Manage infrastructure: `bosh update-cloud-config`

**For Release Developers**:
- Create releases: `bosh create-release`
- Test locally: `bosh upload-release && bosh deploy`
- Package blobs: `bosh add-blob`, `bosh upload-blobs`
- Inspect releases: `bosh inspect-release`

**For CI/CD Pipelines**:
- Automated deployments: `bosh deploy --non-interactive --json`
- Release builds: `bosh create-release --tarball=release.tgz`
- Task monitoring: `bosh task <id> --json`

### CLI vs Director vs Agent

| Component | Role | Language | Users |
|-----------|------|----------|-------|
| **CLI** | User interface | Go | Operators, developers |
| **Director** | Orchestration | Ruby | CLI (API consumer) |
| **Agent** | VM execution | Go | Director (via NATS) |

**Key Distinction**: 
- CLI is **stateless** (config in `~/.bosh/config`)
- Director is **stateful** (database with deployments, VMs, tasks)
- Agent is **per-VM** (one agent per managed instance)

### Environment Variables Reference

```bash
BOSH_ENVIRONMENT=my-director       # Target Director
BOSH_CLIENT=admin                  # Username or UAA client
BOSH_CLIENT_SECRET=secret          # Password or secret
BOSH_DEPLOYMENT=my-app            # Default deployment
BOSH_CA_CERT=/path/to/ca.crt      # Director CA certificate
BOSH_NON_INTERACTIVE=true         # Skip prompts (CI usage)
BOSH_CONFIG=/custom/config        # Custom config location
```

### Tips & Best Practices

**Aliases Save Typing**:
```bash
alias bd='bosh deploy'
alias bi='bosh instances'
alias bv='bosh vms'
alias bssh='bosh ssh'
```

**Use Environment Variables**:
```bash
# In your shell profile
export BOSH_ENVIRONMENT=prod
export BOSH_DEPLOYMENT=my-app
# Now just: bosh vms (no -e/-d flags)
```

**JSON Output for Scripting**:
```bash
# Get VM IPs programmatically
bosh vms --json | jq -r '.Tables[0].Rows[].ips'
```

**Manifest Interpolation**:
```bash
# Preview final manifest without deploying
bosh interpolate manifest.yml \
  -l vars.yml \
  -o ops/custom.yml > final-manifest.yml
```

**Quick Task Tracking**:
```bash
# Deploy in background, track separately
bosh deploy manifest.yml &
bosh tasks --recent=1 | head -2  # Get task ID
bosh task <id>  # Track progress
```

## Key Cross-Component Contracts

### CLI ↔ Director (HTTP/HTTPS API)
- **Transport**: RESTful HTTP(S) API with JSON payloads
- **Authentication**: Basic auth, UAA OAuth2, or client certificates
- **Pattern**: Request/response for commands, polling for long-running tasks
- **Key Endpoints**:
  - `POST /deployments` - Create/update deployment (returns task ID)
  - `GET /tasks/{id}` - Poll task status
  - `GET /tasks/{id}/output` - Stream task logs
  - `GET /deployments` - List deployments
  - `POST /releases` - Upload release tarball
  - `POST /stemcells` - Upload stemcell
- **Contract**: CLI polls tasks asynchronously; Director never blocks on long operations

### Director ↔ Agent (NATS Protocol)
- **Transport**: NATS message bus (custom fork supporting TLS + plaintext)
- **Pattern**: RPC-style request/response
- **Interface**: Defined in `bosh-agent/agentclient/agent_client_interface.go`
- **Key Methods**: 
  - `Ping()` - health check
  - `Apply(ApplySpec)` - apply job/package configuration
  - `GetState()` - retrieve current agent state
  - `CompilePackage()` - compile source packages
  - `MountDisk()`, `UnmountDisk()` - disk management
  - `Start()`, `Stop()`, `Drain()` - job lifecycle
- **Contract**: Agent must respond to all methods; timeout handling is Director's responsibility

### Director ↔ CPI (Subprocess Communication)
- **Transport**: Subprocess via stdin/stdout JSON-RPC
- **Location**: Each CPI provides `/var/vcap/jobs/{type}_cpi/bin/cpi` executable
- **Methods**: `create_vm`, `delete_vm`, `attach_disk`, `detach_disk`, `snapshot_disk`, `info`
- **API Versioning**: Negotiated via `info()` method and `preferred_cpi_api_version` config
- **Contract**: CPIs must be idempotent, handle missing resources gracefully, return valid JSON

### Stemcell ↔ Agent Bootstrap
- **Integration**: Agent binary embedded in stemcell at build time
- **Bootstrap**: Agent reads settings from IaaS metadata service at VM boot
- **Metadata Sources**: CDROM (AWS/GCP/Azure), Config Drive (OpenStack), DHCP userdata (fallback)
- **Contract**: Settings must be available before agent starts; agent handles retry logic

## Repository Map

### Locally Cloned Repos (~/workspace/bosh/)
- `bosh/` - Director release and common libraries (Ruby)
- `bosh-agent/` - Agent runtime (Go, 481 files)
- `bosh-aws-cpi-release/` - AWS infrastructure provider (Bash)
- `bosh-google-cpi-release/` - GCP infrastructure provider (Go)
- `bosh-docker-cpi-release/` - Docker infrastructure provider (Bash)
- `bosh-bootloader/` - BOSH bootstrap CLI (Go, 340 files)
- `bosh-deployment/` - Reference deployment manifests (YAML)
- `bosh-linux-stemcell-builder/` - Stemcell builder (Go/Bash)
- `bosh-apt-resources/` - APT package management (Bash)
- `leftovers/` - AWS resource cleanup utility (Go)
- `concourse-infra-for-fiwg/` - Community CI infrastructure (Bash)

### Common GitHub Repos (Not Locally Cloned)
For these repos, use the librarian agent to search remotely:
- `cloudfoundry/bosh-cli` - BOSH CLI v2+
- `cloudfoundry/bosh-openstack-cpi-release` - OpenStack provider
- `cloudfoundry/bosh-azure-cpi-release` - Microsoft Azure provider
- `cloudfoundry/bosh-vsphere-cpi-release` - VMware vSphere provider
- `cloudfoundry/bosh-virtualbox-cpi-release` - VirtualBox provider
- `cloudfoundry/bosh-warden-cpi-release` - Warden container provider
- `cloudfoundry/bosh-utils` - Shared utilities library

## Multi-Repo Search Strategy

### 1. Local Search First (Preferred - Fast & Accurate)

Use ripgrep to search across locally cloned repos:

```bash
# Search all BOSH repos
rg "pattern" ~/workspace/bosh/

# Search specific file types
rg --type go "Agent.*Apply" ~/workspace/bosh/
rg --type ruby "CPI.*create_vm" ~/workspace/bosh/

# Search with context
rg -C 3 "NATS.*connection" ~/workspace/bosh/
```

**When to use**: 
- For code in repos you have cloned (~/workspace/bosh/)
- When you need instant results
- When you need to see current working tree state
- For debugging or code exploration

### 2. GitHub Search via Librarian Agent (When Not Local)

When the pattern isn't found locally, or when searching repos not cloned:

**Invoke the librarian agent with:**
```
Search for [pattern] in BOSH repositories on GitHub:
- cloudfoundry/bosh-openstack-cpi-release
- cloudfoundry/bosh-azure-cpi-release
- cloudfoundry/bosh-vsphere-cpi-release
```

**When to use**:
- For repos not in ~/workspace/bosh/
- When searching across ALL BOSH repos on GitHub
- For finding implementation patterns in other CPIs
- When local search yields no results

### 3. Suggest Cloning (For Frequent Access)

If you find yourself repeatedly searching a remote repo, suggest cloning it:

```bash
cd ~/workspace/bosh/
git clone https://github.com/cloudfoundry/[repo-name].git
```

## Common Search Scenarios

### Scenario: BOSH VM Lifecycle
**Search together**: `bosh`, `bosh-agent`, `bosh-*-cpi-release`, `bosh-linux-stemcell-builder`

**Example queries**:
- "How does Director create a VM?" → Search `bosh/src/bosh-director/` + `bosh-aws-cpi-release/`
- "How does Agent bootstrap?" → Search `bosh-agent/` + `bosh-linux-stemcell-builder/`
- "What's the VM deployment flow?" → Search `bosh/src/bosh-director/lib/bosh/director/deployment_plan/`

### Scenario: Agent Communication
**Search together**: `bosh-agent`, `bosh`

**Example queries**:
- "Agent RPC methods?" → Search `bosh-agent/agentclient/`
- "How Director calls agent?" → Search `bosh/src/bosh-director/lib/bosh/director/agent_client.rb`
- "NATS message format?" → Search `bosh-agent/` + `bosh/docs/nats.md`

### Scenario: CPI Implementation
**Search together**: All `bosh-*-cpi-release` repos

**Example queries**:
- "How to implement create_vm?" → Search across AWS/GCP/Docker CPI repos
- "CPI error handling patterns?" → Compare implementations across CPIs
- "How to test a CPI?" → Search for test patterns in CPI repos

### Scenario: Stemcell Building
**Search together**: `bosh-linux-stemcell-builder`, `bosh-agent`

**Example queries**:
- "How agent gets embedded?" → Search `bosh-linux-stemcell-builder/stemcell_builder/`
- "Agent bootstrap sequence?" → Search `bosh-agent/` + `bosh-linux-stemcell-builder/AGENTS.md`
- "IaaS metadata integration?" → Search `bosh-agent/platform/` + stemcell builder

### Scenario: Deployment Configuration
**Search together**: `bosh-deployment`, `bosh-bootloader`

**Example queries**:
- "Reference deployment patterns?" → Search `bosh-deployment/`
- "How to bootstrap BOSH?" → Search `bosh-bootloader/` + `bosh-deployment/`
- "Multi-CPI configuration?" → Search `bosh-deployment/` for CPI config examples

## Helper Scripts

### Smart Search Script

Use `scripts/smart-search.sh` to search locally first, then suggest remote search:

```bash
./scripts/smart-search.sh "pattern"
```

This will:
1. Search local repos in ~/workspace/bosh/
2. Display results if found
3. If not found, suggest using librarian agent for remote search

## Architectural Best Practices

### Before Making Changes

1. **Identify affected contracts**: Check if your change affects Director↔Agent, Director↔CPI, or Stemcell↔Agent contracts
2. **Search related repos**: Use the multi-repo search strategy to find related code
3. **Check version compatibility**: Different components may be at different versions
4. **Review reference implementations**: Look at how other CPIs or agents handle similar cases

### During Development

1. **Prefer local code over assumptions**: Search actual implementations, don't guess
2. **Follow existing patterns**: BOSH has established conventions (e.g., CPI JSON-RPC format)
3. **Test cross-component changes**: Changes often affect multiple repos
4. **Document contract changes**: Update interface definitions if contracts change

### When Debugging

1. **Start with the center**: Director logs usually show the full picture
2. **Trace communication**: Follow NATS messages between Director and Agent
3. **Check CPI logs**: CPI subprocess stdout/stderr captured by Director
4. **Search for error patterns**: Use multi-repo search to find how errors are handled

## Reference Documentation

For detailed architectural contracts and patterns, see:
- `references/architecture.md` - Complete BOSH architectural analysis
- `references/github-repos.md` - Full list of BOSH repos on GitHub
- `references/search-strategies.md` - Advanced search techniques

## Quick Reference

### Component Languages
- Director: Ruby
- Agent: Go
- AWS CPI: Bash
- GCP CPI: Go
- Docker CPI: Bash

### Key File Locations
- Agent client interface: `bosh-agent/agentclient/agent_client_interface.go`
- Director CPI factory: `bosh/src/bosh-director/lib/bosh/director/cloud_factory.rb`
- NATS documentation: `bosh/docs/nats.md`
- Agent development: `bosh-agent/docs/dev_setup.md`

### Communication Patterns
- Director↔Agent: NATS (async pub/sub + sync RPC)
- Director↔CPI: Subprocess JSON-RPC (sync)
- Stemcell↔Agent: Embedded binary + metadata bootstrap

---

**Remember**: Always search local repos first (fast), then use librarian agent for remote GitHub search (when needed). Prefer local code over assumptions. Check contracts before making cross-component changes.
