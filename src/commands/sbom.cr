require "./command"
require "../purl"
require "json"

module Shards
  module Commands
    class SBOM < Command
      def run(format : String, output : String?, include_dev : Bool)
        packages = locks.shards

        root_spec = spec

        # Build dependency graph: package_name → [dependency_names]
        dep_graph = build_dependency_graph(packages)

        case format
        when "spdx"
          output_path = output || "#{root_spec.name}.spdx.json"
          generate_spdx(root_spec, packages, dep_graph, output_path)
        when "cyclonedx"
          output_path = output || "#{root_spec.name}.cdx.json"
          generate_cyclonedx(root_spec, packages, dep_graph, output_path)
        else
          raise Error.new("Unknown SBOM format: #{format}. Use 'spdx' or 'cyclonedx'.")
        end
      end

      private def build_dependency_graph(packages : Array(Package)) : Hash(String, Array(String))
        locked_names = packages.map(&.name).to_set
        graph = {} of String => Array(String)

        packages.each do |pkg|
          deps = pkg.spec.dependencies
            .map(&.name)
            .select { |name| locked_names.includes?(name) }
          graph[pkg.name] = deps
        end

        graph
      end

      # --- SPDX 2.3 ---

      private def generate_spdx(root_spec : Spec, packages : Array(Package), dep_graph : Hash(String, Array(String)), output_path : String)
        File.open(output_path, "w") do |file|
          JSON.build(file, indent: 2) do |json|
            json.object do
              json.field "spdxVersion", "SPDX-2.3"
              json.field "dataLicense", "CC0-1.0"
              json.field "SPDXID", "SPDXRef-DOCUMENT"
              json.field "name", "#{root_spec.name}-sbom"
              json.field "documentNamespace", "https://spdx.org/spdxdocs/#{root_spec.name}-#{generate_uuid}"

              json.field "creationInfo" do
                json.object do
                  json.field "created", Time.utc.to_rfc3339
                  json.field "creators" do
                    json.array do
                      json.string "Tool: shards-#{VERSION}"
                    end
                  end
                  json.field "licenseListVersion", "3.25"
                end
              end

              json.field "packages" do
                json.array do
                  # Root package
                  write_spdx_package(json, "SPDXRef-RootPackage", root_spec.name, root_spec.version.to_s,
                    "NOASSERTION", root_spec.license, root_spec.description,
                    root_spec.authors.first?.try(&.name), nil)

                  # Dependency packages
                  packages.each do |pkg|
                    spdx_id = spdx_element_id(pkg.name)
                    source_url = download_location(pkg)
                    purl = PurlGenerator.generate(pkg)

                    write_spdx_package(json, spdx_id, pkg.name, pkg.version.to_s,
                      source_url, pkg.spec.license, pkg.spec.description,
                      pkg.spec.authors.first?.try(&.name), purl)
                  end
                end
              end

              json.field "relationships" do
                json.array do
                  # DOCUMENT describes root
                  write_spdx_relationship(json, "SPDXRef-DOCUMENT", "DESCRIBES", "SPDXRef-RootPackage")

                  # Root depends on direct deps
                  root_dep_names = root_spec.dependencies.map(&.name).to_set
                  packages.each do |pkg|
                    if root_dep_names.includes?(pkg.name)
                      write_spdx_relationship(json, "SPDXRef-RootPackage", "DEPENDS_ON", spdx_element_id(pkg.name))
                    end
                  end

                  # Transitive deps
                  packages.each do |pkg|
                    if deps = dep_graph[pkg.name]?
                      deps.each do |dep_name|
                        write_spdx_relationship(json, spdx_element_id(pkg.name), "DEPENDS_ON", spdx_element_id(dep_name))
                      end
                    end
                  end
                end
              end
            end
          end
        end

        Log.info { "Generated SPDX SBOM: #{output_path}" }
      end

      private def write_spdx_package(json : JSON::Builder, spdx_id : String, name : String, version : String,
                                     download_location : String, license : String?, description : String?,
                                     supplier : String?, purl : String?)
        json.object do
          json.field "SPDXID", spdx_id
          json.field "name", name
          json.field "versionInfo", version
          json.field "downloadLocation", download_location
          json.field "filesAnalyzed", false

          if supplier
            json.field "supplier", "Person: #{supplier}"
          else
            json.field "supplier", "NOASSERTION"
          end

          license_value = license && !license.empty? ? license : "NOASSERTION"
          json.field "licenseDeclared", license_value
          json.field "licenseConcluded", license_value
          json.field "copyrightText", "NOASSERTION"

          if description && !description.empty?
            json.field "description", description
          end

          if purl
            json.field "externalRefs" do
              json.array do
                json.object do
                  json.field "referenceCategory", "PACKAGE-MANAGER"
                  json.field "referenceType", "purl"
                  json.field "referenceLocator", purl
                end
              end
            end
          end
        end
      end

      private def write_spdx_relationship(json : JSON::Builder, element_id : String, relationship_type : String, related_element : String)
        json.object do
          json.field "spdxElementId", element_id
          json.field "relationshipType", relationship_type
          json.field "relatedSpdxElement", related_element
        end
      end

      # --- CycloneDX 1.6 ---

      private def generate_cyclonedx(root_spec : Spec, packages : Array(Package), dep_graph : Hash(String, Array(String)), output_path : String)
        root_bom_ref = root_spec.name

        File.open(output_path, "w") do |file|
          JSON.build(file, indent: 2) do |json|
            json.object do
              json.field "bomFormat", "CycloneDX"
              json.field "specVersion", "1.6"
              json.field "version", 1

              json.field "metadata" do
                json.object do
                  json.field "timestamp", Time.utc.to_rfc3339

                  json.field "tools" do
                    json.object do
                      json.field "components" do
                        json.array do
                          json.object do
                            json.field "type", "application"
                            json.field "name", "shards"
                            json.field "version", VERSION
                          end
                        end
                      end
                    end
                  end

                  json.field "component" do
                    json.object do
                      json.field "type", "application"
                      json.field "name", root_spec.name
                      json.field "version", root_spec.version.to_s
                      json.field "bom-ref", root_bom_ref

                      if description = root_spec.description
                        json.field "description", description unless description.empty?
                      end

                      if license = root_spec.license
                        unless license.empty?
                          json.field "licenses" do
                            json.array do
                              json.object do
                                json.field "license" do
                                  json.object do
                                    json.field "id", license
                                  end
                                end
                              end
                            end
                          end
                        end
                      end

                      unless root_spec.authors.empty?
                        json.field "authors" do
                          json.array do
                            root_spec.authors.each do |author|
                              json.object do
                                json.field "name", author.name
                              end
                            end
                          end
                        end
                      end
                    end
                  end
                end
              end

              json.field "components" do
                json.array do
                  packages.each do |pkg|
                    purl = PurlGenerator.generate(pkg)
                    bom_ref = purl || pkg.name

                    json.object do
                      json.field "type", "library"
                      json.field "name", pkg.name
                      json.field "version", pkg.version.to_s
                      json.field "bom-ref", bom_ref

                      if purl
                        json.field "purl", purl
                      end

                      if description = pkg.spec.description
                        json.field "description", description unless description.empty?
                      end

                      if license = pkg.spec.license
                        unless license.empty?
                          json.field "licenses" do
                            json.array do
                              json.object do
                                json.field "license" do
                                  json.object do
                                    json.field "id", license
                                  end
                                end
                              end
                            end
                          end
                        end
                      end

                      source_url = download_location(pkg)
                      if source_url != "NOASSERTION"
                        json.field "externalReferences" do
                          json.array do
                            json.object do
                              json.field "type", "vcs"
                              json.field "url", source_url
                            end
                          end
                        end
                      end
                    end
                  end
                end
              end

              json.field "dependencies" do
                json.array do
                  # Root dependencies
                  root_dep_names = root_spec.dependencies.map(&.name).to_set
                  json.object do
                    json.field "ref", root_bom_ref
                    json.field "dependsOn" do
                      json.array do
                        packages.each do |pkg|
                          if root_dep_names.includes?(pkg.name)
                            json.string(PurlGenerator.generate(pkg) || pkg.name)
                          end
                        end
                      end
                    end
                  end

                  # Transitive dependencies
                  packages.each do |pkg|
                    pkg_bom_ref = PurlGenerator.generate(pkg) || pkg.name
                    deps = dep_graph[pkg.name]?

                    json.object do
                      json.field "ref", pkg_bom_ref
                      json.field "dependsOn" do
                        json.array do
                          if deps
                            deps.each do |dep_name|
                              dep_pkg = packages.find { |p| p.name == dep_name }
                              if dep_pkg
                                json.string(PurlGenerator.generate(dep_pkg) || dep_name)
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

        Log.info { "Generated CycloneDX SBOM: #{output_path}" }
      end

      # --- Helpers ---

      private def download_location(pkg : Package) : String
        resolver = pkg.resolver
        if resolver.is_a?(PathResolver)
          "NOASSERTION"
        else
          resolver.source
        end
      end

      private def spdx_element_id(name : String) : String
        sanitized = name.gsub(/[^a-zA-Z0-9.\-]/, "-")
        "SPDXRef-Package-#{sanitized}"
      end

      private def generate_uuid : String
        bytes = Random::Secure.random_bytes(16)
        # Set version 4 (random)
        bytes[6] = (bytes[6] & 0x0f) | 0x40
        # Set variant (RFC 4122)
        bytes[8] = (bytes[8] & 0x3f) | 0x80

        hex = bytes.hexstring
        "#{hex[0, 8]}-#{hex[8, 4]}-#{hex[12, 4]}-#{hex[16, 4]}-#{hex[20, 12]}"
      end
    end
  end
end
