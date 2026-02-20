# Terragrunt Config Renderer

## Overview

Offline CLI tool that replicates `_common/base.hcl`'s deep-merge hierarchy logic, rendering the final merged configuration for any resource path **without running Terragrunt**.

No GCP authentication, network access, or Terragrunt initialisation required.

## Quick Start

```bash
# Setup (one-time)
pip3 install python-hcl2
pip3 install pyyaml          # optional, for YAML output

# For --full mode: install hcl2json (Go binary)
go install github.com/tmccombs/hcl2json@latest
# Ensure ~/go/bin is on your PATH

# Add alias to ~/.zshrc (recommended)
echo 'alias tg-render='"'"'python3 "$(git rev-parse --show-toplevel)/scripts/tg-config-renderer.py"'"'"'' >> ~/.zshrc
source ~/.zshrc
```

### Usage

```
# Hierarchy-only mode (default)
tg-render [-f {json,yaml,table}] [-k KEY] [--show-sources] [--show-labels] [resource_path]

# Full config render (template + resource deep merge)
tg-render --full [-f {json,yaml,table}] [-k KEY] [--show-sources] [--show-metadata] [resource_path]
```

| Argument | Description |
|----------|-------------|
| `resource_path` | Path to a resource directory. Defaults to current directory if omitted. |
| `--full` | Render full runtime config (template defaults + resource overrides) |
| `-f`, `--format` | Output format: `json` (default), `yaml`, `table` |
| `-k`, `--key` | Filter to specific key(s) — repeatable |
| `--show-sources` | Show which file each value originated from (hierarchy files in default mode; template vs resource in `--full` mode) |
| `--show-labels` | Show only the computed `standard_labels` |
| `--show-metadata` | Show only the `metadata` dict from inputs (`--full` mode only) |

## How To

### Look up a resource's project, region, and environment

```bash
python3 scripts/tg-config-renderer.py -k project_name -k region -k environment -k environment_type \
  live/non-production/development/platform/dp-dev-01/europe-west2/gke/cluster-01
```

```json
{
  "project_name": "dp-dev-01",
  "region": "europe-west2",
  "environment": "development",
  "environment_type": "non-production"
}
```

### Check what labels a resource will get

```bash
python3 scripts/tg-config-renderer.py --show-labels \
  live/non-production/development/platform/dp-dev-01/europe-west2/gke/cluster-01
```

```json
{
  "standard_labels": {
    "environment": "development",
    "environment_type": "non-production",
    "managed_by": "terragrunt",
    "org": "example-org",
    "project": "dp-dev-01",
    "project_id": "dp-dev-01-d",
    "cost_center": "data_platform",
    "purpose": "data-infrastructure"
  }
}
```

### Trace where each value comes from

```bash
python3 scripts/tg-config-renderer.py -f table --show-sources \
  live/non-production/hub/vpn-gateway/europe-west2/compute/vpn-server
```

```
Key                              Value                                                     Source
-------------------------------------------------------------------------------------------------
merged.org_id                    YOUR_ORG_ID                                                account.hcl
merged.billing_account           YOUR_BILLING_ACCOUNT                                       account.hcl
merged.org_labels.managed_by     terragrunt                                                 account.hcl
merged.org_labels.org            example-org                                                account.hcl
merged.environment               hub                                                        env.hcl
merged.environment_type          infrastructure                                             env.hcl
merged.project_name              vpn-gateway                                                project.hcl
merged.project_id                org-vpn-gateway                                            project.hcl
merged.region                    europe-west2                                               region.hcl
merged.region_short              ew2                                                        region.hcl
...
```

### List all pinned module versions

```bash
python3 scripts/tg-config-renderer.py -f yaml -k module_versions \
  live/non-production/development/platform/dp-dev-01/europe-west2/gke/cluster-01
```

```yaml
module_versions:
  bigquery: v10.1.0
  sql_db: v26.2.1
  vm: v13.2.4
  network: v12.0.0
  gke: v41.0.2
  cloud_nat: v5.4.0
  cloud_dns: v6.0.0
  cloud_armor: v7.0.0
  iam: v8.1.0
  secret_manager: v0.8.0
  cloud_storage: v11.0.0
  cloud_run: v0.22.0
  load_balancer: v12.0.0
  artifact_registry: v0.8.2
  ...
```

### Run from inside a resource directory

```bash
cd live/non-production/development/platform/dp-dev-01/europe-west2/gke/cluster-01
python3 scripts/tg-config-renderer.py
# or with the alias:
tg-render
```

### Pipe through jq for ad-hoc queries

```bash
tg-render live/non-production/development/platform/dp-dev-01/europe-west2/gke/cluster-01 \
  | jq '.merged.project_labels'

tg-render live/non-production/development/platform/dp-dev-01/europe-west2/gke/cluster-01 \
  | jq '.derived.resource_name'
```

## Full Config Render (`--full`)

The `--full` flag renders the complete configuration a resource would receive at Terragrunt runtime — template defaults deep-merged with resource input overrides, hierarchy values substituted, and dependency outputs shown as `#dependency` tokens that display the config path and output variable name.

### Requirements

Requires `hcl2json` on `PATH` (uses HashiCorp's Go HCL library for full HCL2 grammar support):

```bash
go install github.com/tmccombs/hcl2json@latest
# Or download binary from https://github.com/tmccombs/hcl2json/releases
```

### Examples

#### Compute instance (complex template + resource merge)

```bash
tg-render --full live/non-production/development/platform/dp-dev-01/europe-west2/compute/sql-server-01
```

```json
{
  "terraform_source": "git::https://...terraform-google-vm.git//modules/instance_template?ref=v13.2.4",
  "inputs": {
    "machine_type": "n2d-highmem-4",
    "region": "europe-west2",
    "project_id": "#dependency|../../../project, project_id|",
    "name_prefix": "sql-server-01",
    "labels": { "component": "compute", "environment": "development", "..." : "..." },
    "additional_disks": [ "..." ],
    "metadata": { "..." : "..." }
  },
  "unresolved": []
}
```

#### GKE cluster (100+ inputs, 6 dependencies)

```bash
tg-render --full live/non-production/development/platform/dp-dev-01/europe-west2/gke/cluster-01
```

#### Cloud DNS zone (zero unresolved)

```bash
tg-render --full live/non-production/hub/dns-hub/global/cloud-dns/example-zone
```

#### Filter specific keys

```bash
tg-render --full -k machine_type -k labels -k tags \
  live/non-production/development/platform/dp-dev-01/europe-west2/compute/sql-server-01
```

#### Source tracking (template vs resource origin)

```bash
tg-render --full --show-sources \
  live/non-production/development/platform/dp-dev-01/europe-west2/networking/external-ips/nat-ip
```

Shows a `sources` dict mapping each input key to the file it came from (template or resource `terragrunt.hcl`).

#### Table format

```bash
tg-render --full -f table -k machine_type -k region -k project_id \
  live/non-production/development/platform/dp-dev-01/europe-west2/compute/sql-server-01
```

### Output Structure

```json
{
  "terraform_source": "git::https://...?ref=vX.Y.Z",
  "inputs": { "..." : "..." },
  "unresolved": [ "templatefile(...)" ]
}
```

| Field | Description |
|-------|-------------|
| `terraform_source` | Module source URL with resolved version |
| `inputs` | Deep-merged template defaults + resource overrides |
| `unresolved` | Expressions that couldn't be resolved (`templatefile`, complex chained functions) |

### Expression Resolution

| Pattern | Resolution |
|---------|------------|
| `include.base.locals.*` | Substituted from hierarchy merge |
| `local.*` | Resolved from resource/template locals |
| `dependency.X.outputs.Y` | `#dependency\|config_path, output_key\|` token showing the dependency path and output variable |
| `merge(map1, map2)` | Merged if both args resolved |
| `try(expr, fallback)` | Attempt first, fall back to second |
| `concat(list1, list2)` | Concatenated lists |
| `distinct(list)` | Deduplicated list |
| `flatten(list)` | Flattened nested lists |
| `keys(map)` / `values(map)` | Map keys or values as list |
| `sort(list)` | Sorted list |
| `contains(collection, value)` | Boolean membership test |
| `lookup(map, key, default)` | Map key lookup with default |
| `trimsuffix(str, suffix)` | String suffix removed |
| `lower(str)` / `upper(str)` | String case conversion |
| `replace(str, old, new)` | String replacement |
| `basename(get_terragrunt_dir())` | Resource directory name |
| `dirname(get_terragrunt_dir())` | Parent directory path (chainable) |
| `read_terragrunt_config("path")` | Parsed local HCL file (supports `${...}` interpolation in path) |
| String interpolation `"${...}"` | Resolved references substituted |
| `for` expressions (map/list) | Evaluated with iteration variables, nested for-expressions, and `if` conditions |
| Comparison `==` / `!=` | Depth-aware equality/inequality comparison |
| Ternary `cond ? a : b` | Depth-aware evaluation (handles `:` inside strings) |
| `get_env(name, default)` | Resolved to default value (offline — no env access) |
| `templatefile(...)` | `<templatefile(...)>` placeholder |

### Deep Merge Semantics

Matches Terragrunt's `merge_strategy = "deep"`:

- **Maps**: recursively merge (resource keys override template keys at each level)
- **Lists**: resource list replaces template list entirely
- **Scalars**: resource value overrides template value

## How It Works

### Hierarchy Merge Order

The tool walks upward from the resource directory to find each hierarchy file, then flat-merges them in the same order as `_common/base.hcl` (lines 43-49):

```
1. account.hcl  (required)  — org-level: org_id, billing_account, org_labels
2. env.hcl      (optional)  — environment: name, type, env_labels
3. project.hcl  (optional)  — project: project_name, project_id, project_labels
4. region.hcl   (optional)  — region: region, zone, cloud_sql_zones, reserved_internal_ips
5. common.hcl   (required)  — always at _common/common.hcl: module_versions, compute_instance_settings
```

Later files override earlier ones for the same keys.

### Derived Values

After merging, the tool computes derived values matching `base.hcl` lines 54-60:

| Value | Logic |
|-------|-------|
| `name_prefix` | `merged.name_prefix` or `""` |
| `resource_name` | basename of the resource directory |
| `region` | `merged.region` or `"europe-west2"` |
| `environment` | `merged.environment` or `""` |
| `environment_type` | `merged.environment_type` or `""` |
| `project_name` | `merged.project_name` or `""` |
| `module_versions` | `merged.module_versions` or `{}` |

### Standard Labels

Computed matching `base.hcl` lines 64-73:

```
merge(
  { environment, environment_type, managed_by = "terragrunt" },
  merged.org_labels,
  merged.env_labels,
  merged.project_labels
)
```

### Dynamic Expression Handling

`project.hcl` files contain dynamic HCL expressions. The tool evaluates these with a custom regex-based resolver using multi-pass resolution for forward references:

| Pattern | Example | Resolution |
|---------|---------|------------|
| `basename(get_terragrunt_dir())` | dp-dev-01 project.hcl | `"dp-dev-01"` |
| String interpolation | `"${local.project_name}-a"` | `"dp-dev-01-a"` |
| Prefix interpolation | `"org-${local.project_name}"` | `"org-vpn-gateway"` |
| Ternary | `local.name_prefix != "" ? "..." : "org-${local.project}"` | `"org-dns-hub"` |
| `try()` with fallback | `try(local.env_vars.name_prefix, "")` | `""` |
| `read_terragrunt_config(...)` | — | Skipped (redundant) |
| Static values | `"org-vpn-gateway"` | Pass through |

## Output Structure

### Default (no flags)

```json
{
  "merged": { },
  "derived": { },
  "standard_labels": { }
}
```

### With `--show-sources`

```json
{
  "merged": { },
  "derived": { },
  "standard_labels": { },
  "sources": {
    "org_id": "live/non-production/account.hcl",
    "environment": "live/non-production/development/env.hcl",
    "project_name": "live/non-production/development/platform/dp-dev-01/project.hcl",
    "region": "live/non-production/development/platform/dp-dev-01/europe-west2/region.hcl",
    "module_versions": "_common/common.hcl"
  }
}
```

### With `--show-labels`

Only the `standard_labels` dict is returned.

### With `-k KEY`

Only the requested keys from merged + derived are returned.

## Architecture

```
scripts/tg-config-renderer.py

Hierarchy-only mode (default):
├── HclFileLocator         — walk upward from resource path to find each .hcl file
├── HclParser              — parse static HCL via python-hcl2 (regex fallback)
├── HclExpressionEvaluator — multi-pass resolver for dynamic project.hcl expressions
├── HierarchyMerger        — flat merge + derived values + standard_labels
└── OutputFormatter        — JSON / YAML / table rendering

Full config mode (--full):
├── HierarchyMerger        — Stage 1: hierarchy merge (reuses above)
├── Hcl2JsonParser         — Stage 2: parse HCL via hcl2json Go binary
├── IncludeResolver        — identify template path from include blocks
├── DependencyResolver     — extract config_path and mock_outputs from dependency blocks
├── ExpressionResolver     — Stage 3: resolve expressions against hierarchy + mocks
├── DeepMerger             — Terragrunt-compatible recursive deep merge
└── FullConfigRenderer     — orchestrates the 3-stage pipeline
```

## Dependencies

| Package | Required | Purpose |
|---------|----------|---------|
| `python-hcl2` | Yes | Parse HCL2 files into Python dicts |
| `PyYAML` | No | YAML output format (`-f yaml`) |
| `hcl2json` | For `--full` only | Full HCL2 grammar parsing via Go binary |

```bash
pip3 install python-hcl2
pip3 install pyyaml        # optional
go install github.com/tmccombs/hcl2json@latest  # for --full mode
```

## Error Handling

| Error | Cause | Fix |
|-------|-------|-----|
| `path must be inside the live/ hierarchy` | Running from repo root or non-live directory | Provide a path under `live/` |
| `Required hierarchy file 'account.hcl' not found` | Path is above the account level | Navigate deeper into the hierarchy |
| `resource path is not a directory` | Path doesn't exist | Check the path |
| `python-hcl2 module not found` | Missing dependency | `pip3 install python-hcl2` |

## Limitations

### Hierarchy-only mode
- Does not evaluate `generate` blocks or `dependency` outputs
- Does not parse Terraform/OpenTofu variable files (`.tfvars`)
- Only resolves expressions actually found in this repo's `project.hcl` variants
- Nested `try()` or complex conditional expressions may not resolve

### Full config mode (`--full`)
- `for` expressions are evaluated including nested for-expressions, map pivots (`role => members`), and list filters with `if` conditions
- `dependency.X.outputs.Y` is resolved to a `#dependency|config_path, output_key|` token showing the dependency's `config_path` and the output variable name (mock values are no longer used for display)
- `templatefile()` calls are shown as `<templatefile(...)>` placeholders
- Complex chained functions (`split`/`substr`) may not fully resolve
- Multi-pass locals resolution handles forward references and dependency chains between locals
- Does not execute Terragrunt — uses `hcl2json` static parsing only

## Related Documentation

- **[_common/base.hcl](../_common/base.hcl)** — reference implementation this tool replicates
- **[Configuration Templates](CONFIGURATION_TEMPLATES.md)** — template and hierarchy overview
- **[Module Versioning](MODULE_VERSIONING.md)** — centrally pinned module versions
