---
name: sbom
description: Generate a Software Bill of Materials (SBOM) in SPDX or CycloneDX format. Use for supply-chain transparency.
allowed-tools: Bash, Read
user-invocable: true
argument-hint: [--format=spdx|cyclonedx]
---

# Generate Software Bill of Materials (SBOM)

Produce a complete inventory of all project dependencies in an industry-standard SBOM format.

## Steps

1. Verify that `shard.lock` exists in the project root. If it does not, inform the user they need to run `shards-alpha install` first to resolve and lock dependencies.

2. Run the SBOM generation command with the user's requested options:
   ```sh
   shards-alpha sbom [OPTIONS]
   ```

   Available options:
   - `--format=FORMAT` — SBOM format: `spdx` (default) or `cyclonedx`
   - `--output=FILE` — Output file path (default: `{project}-sbom.spdx.json` or `{project}-sbom.cdx.json`)
   - `--include-dev` — Include development dependencies in the SBOM

3. Explain the two supported formats:

   **SPDX 2.3 (default)**:
   - Industry standard maintained by the Linux Foundation
   - Required by many government procurement policies (e.g., US Executive Order 14028)
   - Includes package identifiers, licenses, relationships, and checksums
   - Output is SPDX 2.3 JSON format

   **CycloneDX 1.6**:
   - OWASP standard focused on security and risk analysis
   - Widely supported by vulnerability scanning tools
   - Includes component inventory, licenses, and dependency graph
   - Output is CycloneDX 1.6 JSON format

4. Summarize the generated SBOM:
   - Total number of components listed
   - Document creation timestamp and tool information
   - Note the output file location
   - Mention whether development dependencies were included or excluded

5. Provide context on SBOM usage:
   - SBOMs are increasingly required for software supply chain transparency
   - They can be submitted to customers, auditors, or vulnerability scanning services
   - Both formats are machine-readable and can be ingested by tools like Grype, Trivy, or OWASP Dependency-Track

## Example Invocations

```sh
# Generate SPDX SBOM (default)
shards-alpha sbom

# Generate CycloneDX SBOM
shards-alpha sbom --format=cyclonedx

# Custom output path
shards-alpha sbom --output=artifacts/sbom.spdx.json

# Include development dependencies
shards-alpha sbom --include-dev

# CycloneDX with dev deps and custom output
shards-alpha sbom --format=cyclonedx --include-dev --output=full-sbom.cdx.json
```
