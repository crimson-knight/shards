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
