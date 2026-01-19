# BOSH Repositories on GitHub

This document lists all BOSH-related repositories on GitHub, organized by category.

## Locally Cloned Repos (~/workspace/bosh/)

These repos are available for instant local search via ripgrep:

### Core Components
- **bosh** - BOSH Director and common libraries (Ruby)
- **bosh-agent** - Agent runtime (Go, 481 files)

### Cloud Provider Interfaces (CPIs)
- **bosh-aws-cpi-release** - Amazon Web Services provider (Bash)
- **bosh-google-cpi-release** - Google Cloud Platform provider (Go)
- **bosh-docker-cpi-release** - Docker container provider (Bash)

### Tools and Infrastructure
- **bosh-bootloader** - BOSH bootstrap CLI (Go, 340 files)
- **bosh-deployment** - Reference deployment manifests (YAML)
- **bosh-linux-stemcell-builder** - Stemcell builder (Go/Bash)
- **bosh-apt-resources** - APT package management (Bash)

### Additional
- **leftovers** - AWS resource cleanup utility (Go, 411 files)
- **concourse-infra-for-fiwg** - Community CI infrastructure (Bash)

## GitHub Repos (Not Locally Cloned)

For these repos, use the **librarian agent** to search remotely.

### Additional CPIs
- **cloudfoundry/bosh-openstack-cpi-release** - OpenStack provider
  - Use for: OpenStack-specific CPI implementation patterns
  - Language: Ruby/Bash

- **cloudfoundry/bosh-azure-cpi-release** - Microsoft Azure provider
  - Use for: Azure-specific CPI implementation patterns
  - Language: Go

- **cloudfoundry/bosh-vsphere-cpi-release** - VMware vSphere provider
  - Use for: vSphere-specific CPI implementation patterns
  - Language: Ruby

- **cloudfoundry/bosh-virtualbox-cpi-release** - VirtualBox provider
  - Use for: Local development CPI patterns
  - Language: Ruby

- **cloudfoundry/bosh-warden-cpi-release** - Warden container provider
  - Use for: Container-based CPI patterns
  - Language: Go

- **cloudfoundry/bosh-alicloud-cpi-release** - Alibaba Cloud provider
  - Use for: Alicloud-specific patterns
  - Language: Go

### CLI and Tools
- **cloudfoundry/bosh-cli** - BOSH CLI v2+ (Go)
  - Use for: CLI command implementation, user-facing interfaces
  - Replaces legacy Ruby CLI

- **cloudfoundry/bosh-utils** - Shared utilities library (Go)
  - Use for: Common patterns, utilities used across BOSH components
  - Imported by agent and other Go components

### Additional Infrastructure
- **cloudfoundry/bosh-package-cf-cli-release** - CF CLI packaged as BOSH release
- **cloudfoundry/bosh-package-golang-release** - Go compiler packaged as BOSH release
- **cloudfoundry/bosh-package-ruby-release** - Ruby packaged as BOSH release

### Documentation and Examples
- **cloudfoundry/docs-bosh** - Official BOSH documentation site
- **cloudfoundry/bosh-sample-release** - Sample BOSH release for learning

### Legacy/Deprecated
- **cloudfoundry/bosh-init** - Legacy bootstrap tool (replaced by bosh-cli)
- **cloudfoundry/bosh-lite** - Lightweight BOSH for local development

## Search Strategy by Use Case

### Finding CPI Patterns

**Local CPIs**: AWS, Google, Docker (in ~/workspace/bosh/)
```bash
rg "create_vm" ~/workspace/bosh/bosh-*-cpi-release/
```

**Remote CPIs**: OpenStack, Azure, vSphere
```
Use librarian agent to search:
- cloudfoundry/bosh-openstack-cpi-release
- cloudfoundry/bosh-azure-cpi-release
- cloudfoundry/bosh-vsphere-cpi-release
```

**When to search**: 
- Implementing new CPI methods
- Understanding error handling patterns
- Comparing implementations across providers

### Finding Agent Patterns

**Local**: bosh-agent (in ~/workspace/bosh/)
```bash
rg "agentclient" ~/workspace/bosh/bosh-agent/
```

**Related repos**: bosh-utils (shared utilities)
```
Use librarian agent to search:
- cloudfoundry/bosh-utils
```

**When to search**:
- Understanding agent RPC methods
- Finding platform-specific implementations
- Debugging agent bootstrap issues

### Finding Director Patterns

**Local**: bosh (in ~/workspace/bosh/)
```bash
rg "deployment_plan" ~/workspace/bosh/bosh/src/bosh-director/
```

**When to search**:
- Understanding deployment orchestration
- Finding job/package management logic
- Debugging CPI interaction

### Finding CLI Patterns

**Remote only**: bosh-cli
```
Use librarian agent to search:
- cloudfoundry/bosh-cli
```

**When to search**:
- Understanding user-facing commands
- Finding deployment manifest validation
- Debugging CLI issues

### Finding Stemcell Patterns

**Local**: bosh-linux-stemcell-builder (in ~/workspace/bosh/)
```bash
rg "agent" ~/workspace/bosh/bosh-linux-stemcell-builder/
```

**When to search**:
- Understanding stemcell build process
- Finding agent integration patterns
- Debugging boot issues

## Cloning Additional Repos

If you frequently search a remote repo, consider cloning it:

```bash
cd ~/workspace/bosh/
git clone https://github.com/cloudfoundry/[repo-name].git
```

**Recommended to clone if**:
- You reference it more than 3 times per week
- You need to debug issues in that component
- You're implementing features that interact with it
- You want faster search (local vs remote)

## GitHub Organizations

BOSH repos are primarily in:
- **cloudfoundry/** - Official Cloud Foundry organization
- **cloudfoundry-incubator/** - Experimental/incubating projects

## Useful GitHub Search Queries

When using librarian agent, use these patterns:

```
# Find all CPI implementations of a method
org:cloudfoundry "create_vm" path:*cpi* language:go

# Find agent client usage
org:cloudfoundry "agentclient" language:go

# Find deployment examples
org:cloudfoundry filename:*deployment*.yml path:manifests/

# Find stemcell integration
org:cloudfoundry "stemcell" "agent" language:bash
```

---

**Tip**: Keep this list updated as you discover new relevant repos. If you find yourself repeatedly searching a GitHub repo, add it to your local workspace for faster access.
