# module Shards::Docs::SBOMGeneration

## Software Bill of Materials (SBOM) Generation

The `shards sbom` command generates a machine-readable inventory of all
dependencies in SPDX 2.3 or CycloneDX 1.6 JSON format for compliance
auditing (SOC 2, ISO 27001).

### Usage

```
shards sbom                          # SPDX 2.3 JSON (default)
shards sbom --format=cyclonedx       # CycloneDX 1.6 JSON
shards sbom --output=custom.json     # Custom output path
shards sbom --include-dev            # Include dev dependencies
```

### Data sources

The command reads `shard.lock` for locked versions, then loads each
dependency's `shard.yml` from `lib/<name>/` for metadata (license,
authors, description). Package URLs (purls) are derived from resolver
source URLs, with GitHub/GitLab/Bitbucket sources mapped to their
respective purl types.

See `Commands::SBOM`.

