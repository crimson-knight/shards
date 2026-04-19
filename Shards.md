# module Shards

## Constants

- `AI_DOCS_INFO_FILENAME` = `".ai-docs-info.yml"`
- `ASSISTANT_CONFIG_FILENAME` = `".assistant-config.yml"`
- `BUILD_DATE` = `""`
- `BUILD_SHA1` = `{{ (env("SHARDS_CONFIG_BUILD_COMMIT")) || "" }}`
- `BUILTIN_COMMANDS` = `["build", "run", "check", "diff", "init", "install", "list", "lock", "outdated", "prune", "update", "version", "run-script", "ai-docs", "docs", "sbom", "mcp", "audit", "licenses", "policy", "compliance-report", "mcp-server", "assistant"] of ::String`
- `DEFAULT_COMMAND` = `"install"`
- `DEFAULT_VERSION` = `"0"`
- `FORMATTER` = `::Log::Formatter.new do |entry, io|
  message = entry.message
  package_name = entry.context[:package]?
  if @@colors
    if package_name && entry.severity <= ::Log::Severity::Debug
      ((io << "[") << (package_name.colorize(:blue)).to_s) << "] "
    end
    io << (if color = LOGGER_COLORS[entry.severity]?
      if idx = message.index(' ')
        (message[0...idx].colorize(color)).to_s + message[idx..-1]
      else
        message.colorize(color)
      end
    else
      message
    end)
  else
    (io << entry.severity.label[0]) << ": "
    if package_name && entry.severity <= ::Log::Severity::Debug
      ((io << "[") << package_name) << "] "
    end
    io << message
  end
end`
- `INSTALL_DIR` = `"lib"`
- `LOCK_FILENAME` = `"shard.lock"`
- `Log` = `::Log.for(self)`
- `LOGGER_COLORS` = `{::Log::Severity::Error => :red, ::Log::Severity::Warn => :yellow, ::Log::Severity::Info => :green, ::Log::Severity::Debug => :light_gray}`
- `OVERRIDE_FILENAME` = `"shard.override.yml"`
- `POLICY_FILENAME` = `".shards-policy.yml"`
- `POSTINSTALL_INFO_FILENAME` = `".shards.postinstall"`
- `SPEC_FILENAME` = `"shard.yml"`
- `VERSION` = `{{ (read_file("/home/runner/work/shards/shards/src/../VERSION")).chomp }}`
- `VERSION_AT_FOSSIL_COMMIT` = `/^(\d+[-.][-.a-zA-Z\d]+)\+fossil\.commit\.([0-9a-f]+)$/`
- `VERSION_AT_GIT_COMMIT` = `/^(\d+[-.][-.a-zA-Z\d]+)\+git\.commit\.([0-9a-f]+)$/`
- `VERSION_AT_HG_COMMIT` = `/^(\d+[-.][-.a-zA-Z\d]+)\+hg\.commit\.([0-9a-f]+)$/`
- `VERSION_REFERENCE` = `/^v?\d+[-.][-.a-zA-Z\d]+$/`
- `VERSION_TAG` = `/^v(\d+[-.][-.a-zA-Z\d]+)$/`

## Class Methods

### `ai_docs_info`

### `bin_path`

### `bin_path=(bin_path : String)`

### `cache_path`

### `cache_path=(cache_path : String)`

### `check_and_install_dependencies(path)`

### `cli_options`

### `colors=(colors : Bool)`

### `colors?`

### `crystal_bin`

### `crystal_bin=(crystal_bin : String)`

### `crystal_version`

### `crystal_version=(crystal_version : String)`

### `display_help_and_exit(opts)`

### `frozen=(frozen)`

### `frozen?`

### `global_override_filename`

### `info`

### `install_path`

### `install_path=(install_path : String)`

### `jobs`

### `jobs=(jobs : Int32)`

### `local=(local)`

### `local?`

### `parse_args(args)`

### `postinstall_info`

### `run`

### `run_shards_subcommand(process_name, args)`

### `set_debug_log_level`

### `set_warning_log_level`

### `skip_ai_assistant=(skip_ai_assistant)`

### `skip_ai_assistant?`

### `skip_ai_docs=(skip_ai_docs)`

### `skip_ai_docs?`

### `skip_executables=(skip_executables)`

### `skip_executables?`

### `skip_postinstall=(skip_postinstall)`

### `skip_postinstall?`

### `skip_verify=(skip_verify)`

### `skip_verify?`

### `version_string`

### `with_development=(with_development)`

### `with_development?`

## Types

- `Shards::AIDocsInfo` (class)
- `Shards::AIDocsInstaller` (class)
- `Shards::Any` (module)
- `Shards::AssistantConfig` (module)
- `Shards::AssistantConfigInfo` (class)
- `Shards::AssistantVersions` (module)
- `Shards::ChangeLogger` (class)
- `Shards::Checksum` (module)
- `Shards::ChecksumMismatch` (class)
- `Shards::ClaudeConfig` (module)
- `Shards::Command` (class)
- `Shards::Commands` (module)
- `Shards::Compliance` (module)
- `Shards::ComplianceMCPServer` (class)
- `Shards::Conflict` (class)
- `Shards::CrystalResolver` (class)
- `Shards::Dependency` (class)
- `Shards::DiffReport` (class)
- `Shards::Docs` (module)
- `Shards::Error` (class)
- `Shards::FossilBranchRef` (struct)
- `Shards::FossilCommitRef` (struct)
- `Shards::FossilRef` (struct)
- `Shards::FossilResolver` (class)
- `Shards::FossilTagRef` (struct)
- `Shards::FossilTrunkRef` (struct)
- `Shards::GitBranchRef` (struct)
- `Shards::GitCommitRef` (struct)
- `Shards::GitHeadRef` (struct)
- `Shards::GitRef` (struct)
- `Shards::GitResolver` (class)
- `Shards::GitTagRef` (struct)
- `Shards::Helpers` (module)
- `Shards::HgBookmarkRef` (struct)
- `Shards::HgBranchRef` (struct)
- `Shards::HgCommitRef` (struct)
- `Shards::HgCurrentRef` (struct)
- `Shards::HgRef` (struct)
- `Shards::HgResolver` (class)
- `Shards::HgTagRef` (struct)
- `Shards::IgnoreRule` (struct)
- `Shards::Info` (class)
- `Shards::InvalidLock` (class)
- `Shards::LicensePolicy` (class)
- `Shards::LicenseScanner` (class)
- `Shards::Lock` (class)
- `Shards::LockConflict` (class)
- `Shards::LockfileDiffer` (class)
- `Shards::MCPManager` (class)
- `Shards::MolinilloSolver` (class)
- `Shards::Override` (class)
- `Shards::Package` (class)
- `Shards::PackageScanResult` (struct)
- `Shards::ParseError` (class)
- `Shards::PathResolver` (class)
- `Shards::Policy` (class)
- `Shards::PolicyChecker` (class)
- `Shards::PolicyReport` (class)
- `Shards::PostinstallInfo` (class)
- `Shards::PurlGenerator` (module)
- `Shards::Ref` (struct)
- `Shards::Requirement` (alias)
- `Shards::Resolver` (class)
- `Shards::Script` (module)
- `Shards::Severity` (enum)
- `Shards::SPDX` (module)
- `Shards::Spec` (class)
- `Shards::Target` (class)
- `Shards::Version` (struct)
- `Shards::VersionReq` (struct)
- `Shards::Versions` (module)
- `Shards::Vulnerability` (struct)
- `Shards::VulnerabilityReport` (class)
- `Shards::VulnerabilityScanner` (class)

