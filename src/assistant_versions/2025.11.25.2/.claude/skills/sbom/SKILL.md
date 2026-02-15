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

1. Verify that `shard.lock` exists in the project root. If it does not, inform the user they need to run `shards-alpha install` first.

2. Run the SBOM generation command:
   ```sh
   shards-alpha sbom [OPTIONS]
   ```

   Available options:
   - `--format=FORMAT` — SBOM format: `spdx` (default) or `cyclonedx`
   - `--output=FILE` — Output file path
   - `--include-dev` — Include development dependencies in the SBOM

3. Supported formats:

   **SPDX 2.3 (default)**: Linux Foundation standard, required by US EO 14028.
   **CycloneDX 1.6**: OWASP standard focused on security and risk analysis.

4. Summarize the generated SBOM:
   - Total number of components listed
   - Document creation timestamp
   - Output file location
   - Whether dev dependencies were included or excluded

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
```
