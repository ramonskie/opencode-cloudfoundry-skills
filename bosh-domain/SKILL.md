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
Director (Ruby) -- NATS Message Bus -- Agent (Go, one per VM)
    |                                      |
    +-- ExternalCPI (subprocess)          +-- Local filesystem/disk management
    |   (infrastructure provider)          +-- Package compilation
    |                                      +-- Release/job application
    +-- Database (Postgres)
    +-- Blobstore (S3/GCS/DAV)
```

### Key Components

- **Director** (bosh/): Orchestration engine written in Ruby, manages deployments
- **Agent** (bosh-agent/): Runs on each VM, executes director commands, written in Go
- **CPI** (bosh-*-cpi-release/): Cloud Provider Interface, infrastructure-specific plugins
- **Stemcells** (bosh-linux-stemcell-builder/): Base OS images with embedded agent
- **Bootloader** (bosh-bootloader/): Bootstrap tool to deploy BOSH itself
- **Deployment Manifests** (bosh-deployment/): Reference configurations for various infrastructures

## Key Cross-Component Contracts

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
