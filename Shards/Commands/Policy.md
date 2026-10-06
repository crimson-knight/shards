# class Shards::Commands::Policy

## Constants

- `DEFAULT_POLICY_TEMPLATE` = `"version: 1\n\nrules:\n  sources:\n    allowed_hosts: []\n    deny_path_dependencies: false\n\n  dependencies:\n    blocked: []\n    minimum_versions: {}\n    require_exact: warn\n    publishes_version_ranges: false # Set true for libraries that publish version ranges.\n\n  security:\n    require_license: false\n    block_postinstall: false\n    audit_postinstall: false"`

## Instance Methods

### `run(args : Array(String))`

