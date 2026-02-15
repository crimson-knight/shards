## Complete Implementation Plan: `shards audit` Vulnerability Scanning Command

### 1. Executive Summary

This plan adds a `shards audit` command to shards-alpha that scans locked dependencies for known vulnerabilities using the OSV (Open Source Vulnerabilities) API. The implementation reuses the existing purl generation logic from `src/commands/sbom.cr`, queries the OSV batch API with those purls, and produces reports in terminal, JSON, or SARIF formats. The command integrates into the existing CLI framework via `src/cli.cr` following the same patterns as the `sbom` command.

---

### 2. Codebase Analysis

**Existing patterns observed:**

- Commands extend `Shards::Commands::Command` (defined in `/Users/crimsonknight/open_source_coding_projects/shards/src/commands/command.cr`), which provides `#spec`, `#locks`, `#lockfile?`, and `#path`.
- Commands are invoked via `self.run(path, *args)` class method, which constructs a new instance and calls `#run`.
- The SBOM command at `/Users/crimsonknight/open_source_coding_projects/shards/src/commands/sbom.cr` demonstrates how to access `locks.shards` (an `Array(Package)`) and generate purls from package resolver info.
- The `Package` type at `/Users/crimsonknight/open_source_coding_projects/shards/src/package.cr` exposes `#name`, `#resolver`, `#version`, and `#spec`.
- The `Resolver` base class at `/Users/crimsonknight/open_source_coding_projects/shards/src/resolvers/resolver.cr` exposes `#source` and `#name`, with `PathResolver` being skippable for vulnerability scanning (local deps have no purls).
- The git resolver at `/Users/crimsonknight/open_source_coding_projects/shards/src/resolvers/git.cr` normalizes github/gitlab/bitbucket/codeberg sources to `https://<host>.com/<owner>/<repo>.git` format.
- `BUILTIN_COMMANDS` array in `/Users/crimsonknight/open_source_coding_projects/shards/src/cli.cr` at line 5 must be extended.
- No HTTP client usage exists anywhere in the codebase yet -- Crystal's `HTTP::Client` from stdlib will be the first external network call (aside from git clone operations).
- Logging uses `Shards::Log` with `.info`, `.warn`, `.error`, `.debug` methods.
- Error handling uses `Shards::Error` from `/Users/crimsonknight/open_source_coding_projects/shards/src/errors.cr`.
- The project has no external dependencies beyond `molinillo` (see `/Users/crimsonknight/open_source_coding_projects/shards/shard.yml` line 16-17).

**Key purl generation logic** (from `/Users/crimsonknight/open_source_coding_projects/shards/src/commands/sbom.cr` lines 336-363):

```crystal
private def generate_purl(pkg : Package) : String?
  resolver = pkg.resolver
  source = resolver.source
  version = pkg.version.to_s

  if resolver.is_a?(PathResolver)
    return nil
  end

  owner, repo = parse_owner_repo(source)

  if owner && repo
    host = URI.parse(source).host.try(&.downcase) || ""
    purl_type = case host
                when .includes?("github")    then "github"
                when .includes?("gitlab")    then "gitlab"
                when .includes?("bitbucket") then "bitbucket"
                when .includes?("codeberg")  then "codeberg"
                else                              nil
                end
    if purl_type
      return "pkg:#{purl_type}/#{owner}/#{repo}@#{version}"
    end
  end

  "pkg:generic/#{URI.encode_path(pkg.name)}@#{version}?download_url=#{URI.encode_www_form(source)}"
end
```

This logic must be extracted into a shared module so both `sbom` and `audit` can use it.

---

### 3. Architecture

```
src/cli.cr                    -- Register "audit" command
src/commands/audit.cr         -- CLI command entry point, arg parsing
src/vulnerability_scanner.cr  -- OSV API client, batch queries, caching
src/vulnerability_report.cr   -- Report structs, formatting (terminal/JSON/SARIF)
src/purl.cr                   -- Extracted purl generation (shared by sbom + audit)
spec/unit/audit_spec.cr       -- Unit tests for scanner + report logic
spec/integration/audit_spec.cr -- Integration tests
```

**Data flow:**

```
shard.lock --> Lock.from_file --> Array(Package)
                                    |
                                    v
                              PurlGenerator.generate(pkg) --> Array({Package, String?})
                                    |
                                    v
                              VulnerabilityScanner.scan(purls) --> OSV batch API
                                    |
                                    v
                              Array(VulnerabilityResult)
                                    |
                                    v
                              VulnerabilityReport.format(results, options)
                                    |
                                    v
                              Terminal output / JSON file / SARIF file
                                    |
                                    v
                              Exit code (0 = clean, 1 = vulns found)
```

---

### 4. Detailed File Specifications

#### 4.1. `src/purl.cr` -- Shared Purl Generation Module

**Purpose:** Extract purl logic from SBOM into a reusable module. Both `sbom.cr` and `audit.cr` will use it.

```crystal
require "uri"

module Shards
  module PurlGenerator
    # Returns a Package URL (purl) string for the given package, or nil for
    # path dependencies that have no meaningful remote identity.
    def self.generate(pkg : Package) : String?
      resolver = pkg.resolver
      source = resolver.source
      version = pkg.version.to_s

      return nil if resolver.is_a?(PathResolver)

      owner, repo = parse_owner_repo(source)

      if owner && repo
        host = URI.parse(source).host.try(&.downcase) || ""
        purl_type = case host
                    when .includes?("github")    then "github"
                    when .includes?("gitlab")    then "gitlab"
                    when .includes?("bitbucket") then "bitbucket"
                    when .includes?("codeberg")  then "codeberg"
                    else                              nil
                    end
        if purl_type
          return "pkg:#{purl_type}/#{owner}/#{repo}@#{version}"
        end
      end

      "pkg:generic/#{URI.encode_path(pkg.name)}@#{version}?download_url=#{URI.encode_www_form(source)}"
    end

    # Parses "owner/repo" from a git source URL.
    def self.parse_owner_repo(source : String) : {String?, String?}
      uri = URI.parse(source)
      path = uri.path
      return {nil, nil} unless path

      path = path.lchop('/')
      path = path.rchop(".git") if path.ends_with?(".git")

      parts = path.split('/')
      if parts.size >= 2
        {parts[0], parts[1]}
      else
        {nil, nil}
      end
    rescue
      {nil, nil}
    end
  end
end
```

**Refactoring note:** After creating `src/purl.cr`, the SBOM command's private `generate_purl` and `parse_owner_repo` methods should be replaced with calls to `PurlGenerator.generate(pkg)` and `PurlGenerator.parse_owner_repo(source)`. This is a mechanical substitution -- replace `generate_purl(pkg)` with `PurlGenerator.generate(pkg)` and `parse_owner_repo(source)` with `PurlGenerator.parse_owner_repo(source)` throughout `src/commands/sbom.cr`.

---

#### 4.2. `src/vulnerability_scanner.cr` -- OSV API Client and Cache

**Purpose:** Query the OSV.dev batch API with purls, manage local caching of responses.

```crystal
require "http/client"
require "json"
require "file_utils"

module Shards
  # Represents a single vulnerability found by OSV.
  struct Vulnerability
    getter id : String              # e.g., "GHSA-xxxx-yyyy" or "CVE-2024-1234"
    getter summary : String         # Short human-readable summary
    getter details : String         # Full description
    getter severity : Severity      # Derived severity level
    getter cvss_score : Float64?    # CVSS score if available
    getter affected_versions : Array(String)  # Affected version ranges as strings
    getter references : Array(String)         # URLs to advisories
    getter aliases : Array(String)            # Alternate IDs (CVE <-> GHSA)
    getter published : Time?        # Date published
    getter modified : Time?         # Date last modified

    def initialize(@id, @summary, @details, @severity, @cvss_score,
                   @affected_versions, @references, @aliases,
                   @published, @modified)
    end
  end

  # Severity levels with ordering support.
  enum Severity
    Unknown  # No severity info
    Low
    Medium
    High
    Critical

    def self.parse(str : String) : Severity
      case str.downcase
      when "low"      then Low
      when "medium"   then Medium
      when "high"     then High
      when "critical" then Critical
      else                 Unknown
      end
    end

    # Returns true if this severity is at or above the given threshold.
    def at_or_above?(threshold : Severity) : Bool
      self.value >= threshold.value
    end
  end

  # Holds the scan result for a single package.
  struct PackageScanResult
    getter package : Package
    getter purl : String?
    getter vulnerabilities : Array(Vulnerability)

    def initialize(@package, @purl, @vulnerabilities = [] of Vulnerability)
    end

    def vulnerable? : Bool
      !vulnerabilities.empty?
    end
  end

  # Ignore rule loaded from .shards-audit-ignore or --ignore flag.
  struct IgnoreRule
    getter id : String
    getter reason : String?
    getter expires : Time?

    def initialize(@id, @reason = nil, @expires = nil)
    end

    def expired? : Bool
      if exp = @expires
        Time.utc > exp
      else
        false
      end
    end

    def active? : Bool
      !expired?
    end
  end

  class VulnerabilityScanner
    OSV_BATCH_URL = "https://api.osv.dev/v1/querybatch"
    OSV_QUERY_URL = "https://api.osv.dev/v1/query"
    CACHE_DIR     = ".shards/audit/cache"
    CACHE_TTL     = 1.hour   # Default TTL for cached responses

    getter results : Array(PackageScanResult)

    @cache_dir : String
    @offline : Bool

    def initialize(@path : String, @offline : Bool = false)
      @cache_dir = File.join(@path, CACHE_DIR)
      @results = [] of PackageScanResult
    end

    # Main entry point: scans all packages for vulnerabilities.
    # Returns an array of PackageScanResult, one per package.
    def scan(packages : Array(Package)) : Array(PackageScanResult)
      # Step 1: Build purl-to-package mapping
      purl_map = {} of String => Package
      no_purl_packages = [] of Package

      packages.each do |pkg|
        if purl = PurlGenerator.generate(pkg)
          purl_map[purl] = pkg
        else
          no_purl_packages << pkg
        end
      end

      # Step 2: Query OSV (batch) for all purls
      vuln_map = query_batch(purl_map.keys)

      # Step 3: Build results
      @results = [] of PackageScanResult

      purl_map.each do |purl, pkg|
        vulns = vuln_map[purl]? || [] of Vulnerability
        @results << PackageScanResult.new(pkg, purl, vulns)
      end

      # Path dependencies get empty results
      no_purl_packages.each do |pkg|
        @results << PackageScanResult.new(pkg, nil, [] of Vulnerability)
      end

      @results.sort_by!(&.package.name)
    end

    # Query OSV batch endpoint with an array of purls.
    # Returns a mapping of purl -> Array(Vulnerability).
    private def query_batch(purls : Array(String)) : Hash(String, Array(Vulnerability))
      result = {} of String => Array(Vulnerability)
      return result if purls.empty?

      # Check cache first, collect uncached purls
      uncached_purls = [] of String

      purls.each do |purl|
        if cached = read_cache(purl)
          result[purl] = cached
        elsif @offline
          Log.debug { "No cached data for #{purl} (offline mode)" }
          result[purl] = [] of Vulnerability
        else
          uncached_purls << purl
        end
      end

      return result if uncached_purls.empty?

      # Build the batch query body
      # OSV batch format:
      # { "queries": [ { "package": { "purl": "pkg:..." } }, ... ] }
      body = JSON.build do |json|
        json.object do
          json.field "queries" do
            json.array do
              uncached_purls.each do |purl|
                json.object do
                  json.field "package" do
                    json.object do
                      json.field "purl", purl
                    end
                  end
                end
              end
            end
          end
        end
      end

      # Execute HTTP request
      Log.info { "Querying OSV for #{uncached_purls.size} package(s)..." }
      response_body = http_post(OSV_BATCH_URL, body)

      # Parse batch response
      # OSV batch response format:
      # { "results": [ { "vulns": [ {...}, ... ] }, ... ] }
      parsed = JSON.parse(response_body)
      batch_results = parsed["results"].as_a

      uncached_purls.each_with_index do |purl, idx|
        vulns = [] of Vulnerability

        if idx < batch_results.size
          entry = batch_results[idx]
          if vuln_array = entry["vulns"]?.try(&.as_a)
            vuln_array.each do |v|
              vulns << parse_vulnerability(v)
            end
          end
        end

        result[purl] = vulns
        write_cache(purl, vulns)
      end

      result
    end

    # Parses a single OSV vulnerability JSON object into a Vulnerability struct.
    private def parse_vulnerability(json : JSON::Any) : Vulnerability
      id = json["id"].as_s
      summary = json["summary"]?.try(&.as_s) || ""
      details = json["details"]?.try(&.as_s) || ""

      # Extract severity from database_specific or severity array
      severity = Severity::Unknown
      cvss_score = nil

      if severity_arr = json["severity"]?.try(&.as_a)
        severity_arr.each do |sev|
          if score_str = sev["score"]?.try(&.as_s)
            # CVSS vector string -- parse score from it
            # OSV may provide CVSS score directly
          end
          if sev_type = sev["type"]?.try(&.as_s)
            case sev_type
            when "CVSS_V3"
              if score = parse_cvss_score(sev["score"]?.try(&.as_s))
                cvss_score = score
                severity = cvss_to_severity(score)
              end
            end
          end
        end
      end

      # Fallback: check database_specific.severity
      if severity.unknown?
        if db_sev = json["database_specific"]?.try(&.["severity"]?.try(&.as_s))
          severity = Severity.parse(db_sev)
        end
      end

      # Affected version ranges
      affected_versions = [] of String
      if affected = json["affected"]?.try(&.as_a)
        affected.each do |aff|
          if ranges = aff["ranges"]?.try(&.as_a)
            ranges.each do |range|
              events = range["events"]?.try(&.as_a) || next
              events.each do |event|
                if intro = event["introduced"]?.try(&.as_s)
                  affected_versions << "introduced: #{intro}"
                end
                if fixed = event["fixed"]?.try(&.as_s)
                  affected_versions << "fixed: #{fixed}"
                end
              end
            end
          end
        end
      end

      # References
      references = [] of String
      if refs = json["references"]?.try(&.as_a)
        refs.each do |ref|
          if url = ref["url"]?.try(&.as_s)
            references << url
          end
        end
      end

      # Aliases
      aliases = [] of String
      if alias_arr = json["aliases"]?.try(&.as_a)
        alias_arr.each do |a|
          aliases << a.as_s
        end
      end

      # Timestamps
      published = json["published"]?.try { |t| Time.parse_rfc3339(t.as_s) rescue nil }
      modified = json["modified"]?.try { |t| Time.parse_rfc3339(t.as_s) rescue nil }

      Vulnerability.new(
        id: id,
        summary: summary,
        details: details,
        severity: severity,
        cvss_score: cvss_score,
        affected_versions: affected_versions,
        references: references,
        aliases: aliases,
        published: published,
        modified: modified
      )
    end

    # Parses a CVSS v3 vector string and extracts the numeric score.
    # OSV often provides the vector string; we compute the score.
    # Simplified: use the base score if provided directly.
    private def parse_cvss_score(vector : String?) : Float64?
      return nil unless vector
      # If the vector is just a number, parse it
      vector.to_f64? || nil
    end

    # Maps a numeric CVSS score to a severity level.
    private def cvss_to_severity(score : Float64) : Severity
      case score
      when 0.0..3.9   then Severity::Low
      when 4.0..6.9   then Severity::Medium
      when 7.0..8.9   then Severity::High
      when 9.0..10.0  then Severity::Critical
      else                  Severity::Unknown
      end
    end

    # HTTP POST helper with error handling and timeouts.
    private def http_post(url : String, body : String) : String
      uri = URI.parse(url)
      client = HTTP::Client.new(uri)
      client.connect_timeout = 10.seconds
      client.read_timeout = 30.seconds

      headers = HTTP::Headers{
        "Content-Type" => "application/json",
        "User-Agent"   => "shards-alpha/#{VERSION}",
      }

      response = client.post(uri.request_target, headers: headers, body: body)

      unless response.success?
        raise Error.new("OSV API request failed with status #{response.status_code}: #{response.body[0..200]}")
      end

      response.body
    ensure
      client.try(&.close)
    end

    # Force refresh all cached data.
    def update_cache(packages : Array(Package))
      clear_cache
      scan(packages)
    end

    # --- Cache methods ---

    private def cache_key(purl : String) : String
      # Use a hash of the purl as the filename to avoid filesystem issues
      Digest::SHA256.hexdigest(purl)
    end

    private def cache_path(purl : String) : String
      File.join(@cache_dir, "#{cache_key(purl)}.json")
    end

    private def read_cache(purl : String) : Array(Vulnerability)?
      path = cache_path(purl)
      return nil unless File.exists?(path)

      # Check TTL
      mtime = File.info(path).modification_time
      return nil if (Time.utc - mtime) > CACHE_TTL

      json = JSON.parse(File.read(path))
      vulns = [] of Vulnerability
      json.as_a.each do |v|
        vulns << parse_cached_vulnerability(v)
      end
      vulns
    rescue
      nil
    end

    private def write_cache(purl : String, vulns : Array(Vulnerability))
      Dir.mkdir_p(@cache_dir)
      path = cache_path(purl)

      data = JSON.build do |json|
        json.array do
          vulns.each do |v|
            json.object do
              json.field "id", v.id
              json.field "summary", v.summary
              json.field "details", v.details
              json.field "severity", v.severity.to_s.downcase
              json.field "cvss_score", v.cvss_score
              json.field "affected_versions" do
                json.array { v.affected_versions.each { |av| json.string av } }
              end
              json.field "references" do
                json.array { v.references.each { |r| json.string r } }
              end
              json.field "aliases" do
                json.array { v.aliases.each { |a| json.string a } }
              end
              json.field "published", v.published.try(&.to_rfc3339)
              json.field "modified", v.modified.try(&.to_rfc3339)
            end
          end
        end
      end

      File.write(path, data)
    end

    private def parse_cached_vulnerability(json : JSON::Any) : Vulnerability
      Vulnerability.new(
        id: json["id"].as_s,
        summary: json["summary"].as_s,
        details: json["details"].as_s,
        severity: Severity.parse(json["severity"].as_s),
        cvss_score: json["cvss_score"]?.try(&.as_f?),
        affected_versions: json["affected_versions"].as_a.map(&.as_s),
        references: json["references"].as_a.map(&.as_s),
        aliases: json["aliases"].as_a.map(&.as_s),
        published: json["published"]?.try { |t| t.as_s?.try { |s| Time.parse_rfc3339(s) rescue nil } },
        modified: json["modified"]?.try { |t| t.as_s?.try { |s| Time.parse_rfc3339(s) rescue nil } }
      )
    end

    private def clear_cache
      Shards::Helpers.rm_rf(@cache_dir) if Dir.exists?(@cache_dir)
    end

    # --- Ignore file parsing ---

    def self.load_ignore_rules(path : String) : Array(IgnoreRule)
      rules = [] of IgnoreRule
      return rules unless File.exists?(path)

      yaml = YAML.parse(File.read(path))
      if ignores = yaml["ignores"]?.try(&.as_a)
        ignores.each do |entry|
          id = entry["id"].as_s
          reason = entry["reason"]?.try(&.as_s)
          expires = entry["expires"]?.try { |e| Time.parse(e.as_s, "%Y-%m-%d", Time::Location::UTC) rescue nil }
          rules << IgnoreRule.new(id, reason, expires)
        end
      end

      rules
    end
  end
end
```

**Key design decisions:**

1. **Batch API usage:** All purls are sent in a single batch request to `POST /v1/querybatch` rather than individual requests. This minimizes latency. The OSV batch API accepts up to 1000 queries per request; for projects with more dependencies, batching in groups of 1000 would be needed (Crystal shard projects rarely exceed 100 deps).

2. **Cache strategy:** Each purl's vulnerability response is cached as a JSON file in `.shards/audit/cache/` using a SHA256 hash of the purl as the filename. Cache TTL defaults to 1 hour. This approach avoids a single monolithic cache file that could get corrupted.

3. **No new dependencies:** Uses Crystal stdlib's `HTTP::Client`, `JSON`, `Digest::SHA256` -- no new shard dependencies needed.

4. **Offline mode:** When `--offline` is specified, only cached data is used. Missing cache entries result in empty vulnerability lists (not errors).

---

#### 4.3. `src/vulnerability_report.cr` -- Report Formatting

**Purpose:** Format scan results for output in terminal (colorized), JSON, or SARIF formats.

```crystal
require "json"
require "colorize"

module Shards
  class VulnerabilityReport
    getter results : Array(PackageScanResult)
    getter ignore_rules : Array(IgnoreRule)
    getter min_severity : Severity
    getter fail_above : Severity?

    @ignored_count : Int32 = 0
    @filtered_count : Int32 = 0

    def initialize(@results, @ignore_rules = [] of IgnoreRule,
                   @min_severity = Severity::Unknown,
                   @fail_above : Severity? = nil)
    end

    # Returns filtered results (after applying ignore rules and severity filter).
    def filtered_results : Array(PackageScanResult)
      @results.map do |result|
        filtered_vulns = result.vulnerabilities.select do |vuln|
          active_ignore = @ignore_rules.find { |rule| rule.id == vuln.id && rule.active? }
          if active_ignore
            @ignored_count += 1
            next false
          end

          # Check aliases too
          alias_ignored = vuln.aliases.any? { |a| @ignore_rules.any? { |rule| rule.id == a && rule.active? } }
          if alias_ignored
            @ignored_count += 1
            next false
          end

          if vuln.severity.at_or_above?(@min_severity)
            true
          else
            @filtered_count += 1
            false
          end
        end

        PackageScanResult.new(result.package, result.purl, filtered_vulns)
      end
    end

    # Returns appropriate exit code.
    # 0 = no vulnerabilities above threshold
    # 1 = vulnerabilities found above threshold
    def exit_code : Int32
      threshold = @fail_above || Severity::Low
      filtered = filtered_results
      has_vulns = filtered.any? { |r| r.vulnerabilities.any? { |v| v.severity.at_or_above?(threshold) } }
      has_vulns ? 1 : 0
    end

    # Total vulnerability count after filtering.
    def vulnerability_count : Int32
      filtered_results.sum(&.vulnerabilities.size)
    end

    # --- Terminal Output ---

    def to_terminal(io : IO = STDOUT)
      filtered = filtered_results
      vulnerable_packages = filtered.select(&.vulnerable?)
      total_vulns = filtered.sum(&.vulnerabilities.size)
      total_packages = @results.size

      if vulnerable_packages.empty?
        io.puts "No known vulnerabilities found in #{total_packages} package(s).".colorize(:green)
        print_stats(io)
        return
      end

      io.puts "Found #{total_vulns} vulnerability(ies) in #{vulnerable_packages.size} package(s):".colorize(:red).bold
      io.puts

      vulnerable_packages.each do |result|
        io.puts "  #{result.package.name} (#{result.package.version})".colorize(:yellow).bold
        if purl = result.purl
          io.puts "    purl: #{purl}".colorize(:light_gray)
        end

        result.vulnerabilities.sort_by { |v| -v.severity.value }.each do |vuln|
          severity_str = severity_badge(vuln.severity)
          io.puts "    #{severity_str} #{vuln.id}"
          io.puts "      #{vuln.summary}" unless vuln.summary.empty?

          unless vuln.aliases.empty?
            io.puts "      Aliases: #{vuln.aliases.join(", ")}".colorize(:light_gray)
          end

          if ref = vuln.references.first?
            io.puts "      More info: #{ref}".colorize(:light_gray)
          end
          io.puts
        end
      end

      print_stats(io)
    end

    private def severity_badge(severity : Severity) : String
      case severity
      when .critical? then "[CRITICAL]".colorize(:red).bold.to_s
      when .high?     then "[HIGH]".colorize(:red).to_s
      when .medium?   then "[MEDIUM]".colorize(:yellow).to_s
      when .low?      then "[LOW]".colorize(:light_gray).to_s
      else                 "[UNKNOWN]".colorize(:dark_gray).to_s
      end
    end

    private def print_stats(io : IO)
      parts = [] of String
      parts << "#{@ignored_count} ignored" if @ignored_count > 0
      parts << "#{@filtered_count} below severity threshold" if @filtered_count > 0
      unless parts.empty?
        io.puts "(#{parts.join(", ")})".colorize(:dark_gray)
      end
    end

    # --- JSON Output ---

    def to_json(io : IO)
      filtered = filtered_results

      JSON.build(io, indent: 2) do |json|
        json.object do
          json.field "schema_version", "1.0.0"
          json.field "tool", "shards-alpha"
          json.field "tool_version", VERSION
          json.field "timestamp", Time.utc.to_rfc3339

          json.field "summary" do
            json.object do
              json.field "total_packages", @results.size
              json.field "vulnerable_packages", filtered.count(&.vulnerable?)
              json.field "total_vulnerabilities", filtered.sum(&.vulnerabilities.size)
              json.field "ignored", @ignored_count
              json.field "filtered_by_severity", @filtered_count
            end
          end

          json.field "packages" do
            json.array do
              filtered.select(&.vulnerable?).each do |result|
                json.object do
                  json.field "name", result.package.name
                  json.field "version", result.package.version.to_s
                  json.field "purl", result.purl

                  json.field "vulnerabilities" do
                    json.array do
                      result.vulnerabilities.each do |vuln|
                        json.object do
                          json.field "id", vuln.id
                          json.field "summary", vuln.summary
                          json.field "severity", vuln.severity.to_s.downcase
                          json.field "cvss_score", vuln.cvss_score
                          json.field "aliases" do
                            json.array { vuln.aliases.each { |a| json.string a } }
                          end
                          json.field "references" do
                            json.array { vuln.references.each { |r| json.string r } }
                          end
                          json.field "published", vuln.published.try(&.to_rfc3339)
                          json.field "modified", vuln.modified.try(&.to_rfc3339)
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end

    # --- SARIF Output ---
    # SARIF 2.1.0 format for integration with GitHub Advanced Security, Azure DevOps, etc.

    def to_sarif(io : IO)
      filtered = filtered_results

      JSON.build(io, indent: 2) do |json|
        json.object do
          json.field "$schema", "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/main/sarif-2.1/schema/sarif-schema-2.1.0.json"
          json.field "version", "2.1.0"

          json.field "runs" do
            json.array do
              json.object do
                json.field "tool" do
                  json.object do
                    json.field "driver" do
                      json.object do
                        json.field "name", "shards-alpha audit"
                        json.field "version", VERSION
                        json.field "informationUri", "https://github.com/crimson-knight/shards"

                        # Rules: one per unique vulnerability ID
                        json.field "rules" do
                          json.array do
                            unique_vulns = filtered.flat_map(&.vulnerabilities).uniq(&.id)
                            unique_vulns.each do |vuln|
                              json.object do
                                json.field "id", vuln.id
                                json.field "shortDescription" do
                                  json.object do
                                    json.field "text", vuln.summary.empty? ? vuln.id : vuln.summary
                                  end
                                end
                                json.field "fullDescription" do
                                  json.object do
                                    json.field "text", vuln.details.empty? ? vuln.summary : vuln.details
                                  end
                                end
                                json.field "defaultConfiguration" do
                                  json.object do
                                    json.field "level", sarif_level(vuln.severity)
                                  end
                                end
                                unless vuln.references.empty?
                                  json.field "helpUri", vuln.references.first
                                end
                              end
                            end
                          end
                        end
                      end
                    end
                  end
                end

                # Results
                json.field "results" do
                  json.array do
                    filtered.select(&.vulnerable?).each do |result|
                      result.vulnerabilities.each do |vuln|
                        json.object do
                          json.field "ruleId", vuln.id
                          json.field "level", sarif_level(vuln.severity)
                          json.field "message" do
                            json.object do
                              json.field "text", "#{result.package.name}@#{result.package.version} is affected by #{vuln.id}: #{vuln.summary}"
                            end
                          end
                          json.field "locations" do
                            json.array do
                              json.object do
                                json.field "physicalLocation" do
                                  json.object do
                                    json.field "artifactLocation" do
                                      json.object do
                                        json.field "uri", "shard.lock"
                                      end
                                    end
                                  end
                                end
                              end
                            end
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end

    private def sarif_level(severity : Severity) : String
      case severity
      when .critical?, .high? then "error"
      when .medium?           then "warning"
      when .low?              then "note"
      else                         "none"
      end
    end
  end
end
```

---

#### 4.4. `src/commands/audit.cr` -- CLI Command

**Purpose:** Entry point for `shards audit`, handles argument parsing, orchestrates scanning, and outputs results.

```crystal
require "./command"
require "../vulnerability_scanner"
require "../vulnerability_report"
require "../purl"
require "digest/sha256"

module Shards
  module Commands
    class Audit < Command
      IGNORE_FILENAME = ".shards-audit-ignore"

      def run(
        format : String = "terminal",
        severity : String? = nil,
        ignore_ids : Array(String) = [] of String,
        ignore_file : String? = nil,
        fail_above : String? = nil,
        offline : Bool = false,
        update_db : Bool = false
      )
        # Validate format
        unless format.in?("terminal", "json", "sarif")
          raise Error.new("Unknown audit format: #{format}. Use 'terminal', 'json', or 'sarif'.")
        end

        # Parse severity filter
        min_severity = if sev = severity
                         Severity.parse(sev)
                       else
                         Severity::Unknown
                       end

        # Parse fail threshold
        fail_threshold = if fa = fail_above
                           Severity.parse(fa)
                         else
                           Severity::Low  # Default: fail on any vuln
                         end

        # Load packages from lockfile
        packages = locks.shards

        if packages.empty?
          Log.info { "No dependencies to audit." }
          return
        end

        Log.info { "Auditing #{packages.size} package(s) for vulnerabilities..." }

        # Create scanner
        scanner = VulnerabilityScanner.new(path, offline: offline)

        # Force cache refresh if requested
        if update_db
          scanner.update_cache(packages)
        else
          scanner.scan(packages)
        end

        results = scanner.results

        # Load ignore rules
        ignore_rules = load_ignore_rules(ignore_ids, ignore_file)

        # Build report
        report = VulnerabilityReport.new(
          results,
          ignore_rules: ignore_rules,
          min_severity: min_severity,
          fail_above: fail_threshold
        )

        # Output
        case format
        when "terminal"
          report.to_terminal
        when "json"
          report.to_json(STDOUT)
          puts  # trailing newline
        when "sarif"
          report.to_sarif(STDOUT)
          puts
        end

        # Exit with appropriate code
        code = report.exit_code
        exit(code) if code != 0
      end

      private def load_ignore_rules(cli_ids : Array(String), ignore_file_path : String?) : Array(IgnoreRule)
        rules = [] of IgnoreRule

        # CLI --ignore flag
        cli_ids.each do |id|
          rules << IgnoreRule.new(id, reason: "Ignored via CLI flag")
        end

        # Ignore file (explicit path or default)
        file_path = ignore_file_path || File.join(path, IGNORE_FILENAME)
        rules.concat(VulnerabilityScanner.load_ignore_rules(file_path))

        rules
      end
    end
  end
end
```

---

#### 4.5. Modifications to `src/cli.cr`

**Changes required:**

1. Add `"audit"` to the `BUILTIN_COMMANDS` array (line 5).
2. Add a help line for the audit command in `display_help_and_exit` (around line 44).
3. Add a `when "audit"` case in the command dispatch (around line 153).

**Specific changes:**

In `BUILTIN_COMMANDS` (line 5-22), add `"audit"`:
```crystal
BUILTIN_COMMANDS = %w[
  build
  run
  check
  init
  install
  list
  lock
  outdated
  prune
  update
  version
  run-script
  ai-docs
  docs
  sbom
  mcp
  audit
]
```

In `display_help_and_exit` (after line 44), add:
```crystal
          audit [options]                         - Audit dependencies for known vulnerabilities.
```

In the command dispatch `case` (after the `sbom` case ending at line 164), add:
```crystal
when "audit"
  audit_format = "terminal"
  audit_severity = nil : String?
  audit_ignore_ids = [] of String
  audit_ignore_file = nil : String?
  audit_fail_above = nil : String?
  audit_offline = false
  audit_update_db = false
  args[1..-1].each do |arg|
    case arg
    when .starts_with?("--format=")    then audit_format = arg.split("=", 2).last
    when .starts_with?("--severity=")  then audit_severity = arg.split("=", 2).last
    when .starts_with?("--ignore=")    then audit_ignore_ids = arg.split("=", 2).last.split(",")
    when .starts_with?("--ignore-file=") then audit_ignore_file = arg.split("=", 2).last
    when .starts_with?("--fail-above=") then audit_fail_above = arg.split("=", 2).last
    when "--offline"                    then audit_offline = true
    when "--update-db"                  then audit_update_db = true
    end
  end
  Commands::Audit.run(path, audit_format, audit_severity, audit_ignore_ids,
    audit_ignore_file, audit_fail_above, audit_offline, audit_update_db)
```

---

#### 4.6. Modifications to `src/commands/sbom.cr`

**Changes required:** Replace the private `generate_purl` and `parse_owner_repo` methods with calls to the shared `PurlGenerator` module.

1. Add `require "../purl"` at the top.
2. Replace all calls to `generate_purl(pkg)` with `PurlGenerator.generate(pkg)`.
3. Replace all calls to `parse_owner_repo(source)` with `PurlGenerator.parse_owner_repo(source)`.
4. Remove the private `generate_purl` and `parse_owner_repo` method definitions (lines 336-384).

---

#### 4.7. Modifications to `src/shards.cr`

No changes needed. The `require "./cli"` at the bottom of `/Users/crimsonknight/open_source_coding_projects/shards/src/shards.cr` triggers `require "./commands/*"` inside `src/cli.cr`, which will automatically pick up `src/commands/audit.cr`.

---

#### 4.8. `.shards-audit-ignore` File Format

```yaml
# Vulnerability ignore rules for shards audit
# Format: YAML with 'ignores' key containing a list of rules
#
# Each rule must have:
#   id:      The vulnerability ID to ignore (GHSA-*, CVE-*, OSV-*)
#   reason:  Why this vulnerability is being ignored (required for documentation)
#   expires: Optional expiration date (YYYY-MM-DD) after which the rule stops applying
#
# Example:
ignores:
  - id: GHSA-xxxx-yyyy-zzzz
    reason: "Not exploitable in our usage -- we never pass user input to the affected function"
    expires: 2025-06-01
  - id: CVE-2024-1234
    reason: "Mitigated by network controls"
```

---

### 5. Implementation Sequence

**Phase 1: Foundation (shared purl module)**
1. Create `src/purl.cr` with `PurlGenerator` module.
2. Refactor `src/commands/sbom.cr` to use `PurlGenerator` instead of private methods.
3. Run existing SBOM tests to verify no regression.

**Phase 2: Core scanning**
4. Create `src/vulnerability_scanner.cr` with `VulnerabilityScanner`, `Vulnerability`, `Severity`, `PackageScanResult`, and `IgnoreRule`.
5. Implement OSV batch API querying with HTTP::Client.
6. Implement response parsing and severity mapping.
7. Implement file-system cache with TTL.
8. Implement ignore file parsing.

**Phase 3: Report formatting**
9. Create `src/vulnerability_report.cr` with terminal, JSON, and SARIF formatters.
10. Implement severity filtering and ignore rule application in the report layer.
11. Implement exit code logic.

**Phase 4: CLI integration**
12. Create `src/commands/audit.cr` with argument parsing and orchestration.
13. Modify `src/cli.cr` to register the audit command and dispatch arguments.

**Phase 5: Testing**
14. Create `spec/unit/audit_spec.cr` with unit tests for:
    - `PurlGenerator.generate` with various resolver types
    - `Severity.parse` and `Severity#at_or_above?`
    - `VulnerabilityScanner.load_ignore_rules` with valid/expired rules
    - `VulnerabilityReport#exit_code` with various scenarios
    - JSON and SARIF output validation
15. Create `spec/integration/audit_spec.cr` with integration tests for:
    - Running `shards audit` on a project with dependencies
    - `--format=json` output structure validation
    - `--format=sarif` output structure validation
    - `--offline` mode behavior
    - Error handling when no lockfile exists
    - Exit code behavior

---

### 6. Potential Challenges and Mitigations

1. **Network failures during OSV API calls**: The `http_post` method includes connect and read timeouts (10s/30s). Transient failures should produce a clear error message. Consider adding retry logic (1-2 retries with backoff) similar to the `git_retry` pattern in the git resolver.

2. **OSV response format changes**: The OSV v1 API is stable, but defensive parsing (using `?.try` chains) protects against missing fields. The `parse_vulnerability` method already handles missing severity, references, and timestamps gracefully.

3. **CVSS score extraction**: OSV may provide CVSS vectors (strings like `CVSS:3.1/AV:N/AC:L/...`) rather than numeric scores. The initial implementation uses a simplified approach; a future enhancement could parse the vector string into a score. The `database_specific.severity` fallback handles most cases where GHSA provides severity directly as a string.

4. **Large dependency trees**: Crystal projects rarely have more than 100 dependencies. The OSV batch API supports up to 1000 queries per request, so no batching logic is needed initially. If needed, chunking can be added later.

5. **Path dependencies**: Correctly skipped (no purl, no API query, no vulnerability results). Documented in output as "N/A" if terminal format.

6. **Cache directory conflicts**: Using SHA256 of the purl as the cache filename avoids filesystem issues with special characters in purls. The `.shards/audit/cache/` directory is under the project's `.shards` directory (which already exists for git clone caching).

7. **Crystal stdlib HTTP::Client TLS**: Crystal's HTTP::Client supports TLS out of the box. The OSV API uses HTTPS, so this works without additional configuration.

---

### 7. Success Criteria

1. `shards audit` runs successfully on a project with a `shard.lock` and reports vulnerabilities (or "no vulnerabilities found").
2. `shards audit --format=json` produces valid JSON output matching the schema defined in `to_json`.
3. `shards audit --format=sarif` produces valid SARIF 2.1.0 output.
4. `shards audit --severity=high` filters out low/medium vulnerabilities.
5. `shards audit --ignore=GHSA-xxxx` suppresses the specified vulnerability from output.
6. `shards audit --offline` works with cached data and does not make network requests.
7. `shards audit --update-db` forces a cache refresh.
8. The command exits with code 0 when no vulnerabilities are found and code 1 when vulnerabilities are found.
9. `shards audit --fail-above=critical` only exits with code 1 if critical vulnerabilities are found.
10. A `.shards-audit-ignore` file with expired rules correctly re-surfaces previously ignored vulnerabilities.
11. The existing `shards sbom` tests pass after the purl extraction refactor.
12. Path dependencies are handled gracefully (skipped, no errors).
13. The command fails gracefully with a clear error when no `shard.lock` exists (using the existing `locks` method from `Command` base class which raises `Error.new("Missing shard.lock...")`).

---

### 8. Validation Steps

1. **Build**: `crystal build src/shards.cr -o bin/shards-alpha` completes without errors.
2. **Help text**: `bin/shards-alpha --help` shows the `audit` command in the command list.
3. **No lockfile error**: In a directory without `shard.lock`, `bin/shards-alpha audit` shows "Missing shard.lock" error.
4. **Basic scan**: In a Crystal project with dependencies, `bin/shards-alpha audit` queries OSV and displays results.
5. **JSON output**: `bin/shards-alpha audit --format=json | jq .` validates and pretty-prints JSON.
6. **SARIF output**: `bin/shards-alpha audit --format=sarif | jq .` validates.
7. **Severity filter**: `bin/shards-alpha audit --severity=critical` shows only critical vulns.
8. **Ignore by CLI**: `bin/shards-alpha audit --ignore=CVE-2024-1234` suppresses that CVE.
9. **Ignore by file**: Create `.shards-audit-ignore` with a rule, verify it is applied.
10. **Cache**: Run audit twice; second run should be faster (check log output for "Querying OSV" message).
11. **Offline**: `bin/shards-alpha audit --offline` works after a cached run.
12. **Exit code**: `echo $?` after audit shows 0 for clean, 1 for vulnerable.
13. **SBOM regression**: `crystal spec spec/unit/sbom_spec.cr` and `crystal spec spec/integration/sbom_spec.cr` pass.
14. **Unit tests**: `crystal spec spec/unit/audit_spec.cr` passes.
15. **Integration tests**: `crystal spec spec/integration/audit_spec.cr` passes.

---

### Critical Files for Implementation
- `/Users/crimsonknight/open_source_coding_projects/shards/src/commands/sbom.cr` - Contains the purl generation logic to extract into a shared module, and serves as the primary pattern for the new command
- `/Users/crimsonknight/open_source_coding_projects/shards/src/cli.cr` - Must be modified to register the audit command in BUILTIN_COMMANDS, add help text, and add argument parsing/dispatch
- `/Users/crimsonknight/open_source_coding_projects/shards/src/commands/command.cr` - Base class that the Audit command will extend; provides locks, spec, path accessors
- `/Users/crimsonknight/open_source_coding_projects/shards/src/package.cr` - Package type that holds resolver and version info needed for purl generation and result association
- `/Users/crimsonknight/open_source_coding_projects/shards/spec/integration/sbom_spec.cr` - Test patterns to follow for integration tests, and must be verified for regression after purl refactor