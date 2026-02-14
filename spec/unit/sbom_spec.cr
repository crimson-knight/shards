require "./spec_helper"
require "json"
require "../../src/version"
require "../../src/commands/sbom"

module Shards
  describe Commands::SBOM do
    describe "SPDX generation" do
      it "generates valid SPDX JSON for git dependencies" do
        create_git_repository "sbom_lib", "1.0.0"

        Dir.cd(tmp_path) do
          Dir.mkdir_p("sbom_project/lib/sbom_lib")

          File.write "sbom_project/shard.yml", {
            name: "sbom_project", version: "0.1.0",
            dependencies: {sbom_lib: {git: git_url(:sbom_lib)}},
          }.to_yaml

          File.write "sbom_project/shard.lock", YAML.dump({
            version: Lock::CURRENT_VERSION,
            shards:  {sbom_lib: {git: git_url(:sbom_lib), version: "1.0.0"}},
          })

          # Copy shard.yml to lib so spec can be read
          File.write "sbom_project/lib/sbom_lib/shard.yml", {
            name: "sbom_lib", version: "1.0.0",
          }.to_yaml

          # Write .shards.info
          File.write "sbom_project/lib/.shards.info", YAML.dump({
            version: "1.0",
            shards:  {sbom_lib: {git: git_url(:sbom_lib), version: "1.0.0"}},
          })

          cmd = Commands::SBOM.new("sbom_project")
          cmd.run("spdx", "sbom_project/test-output.spdx.json", false)

          File.exists?("sbom_project/test-output.spdx.json").should be_true
          json = JSON.parse(File.read("sbom_project/test-output.spdx.json"))

          json["spdxVersion"].should eq("SPDX-2.3")
          json["dataLicense"].should eq("CC0-1.0")
          json["name"].should eq("sbom_project-sbom")

          packages = json["packages"].as_a
          packages.size.should eq(2) # root + sbom_lib

          root = packages.find { |p| p["name"].as_s == "sbom_project" }.not_nil!
          root["SPDXID"].should eq("SPDXRef-RootPackage")
          root["filesAnalyzed"].should eq(false)

          dep = packages.find { |p| p["name"].as_s == "sbom_lib" }.not_nil!
          dep["versionInfo"].should eq("1.0.0")
          dep["downloadLocation"].as_s.should_not eq("NOASSERTION")
        end
      end

      it "generates valid CycloneDX JSON for git dependencies" do
        create_git_repository "cdx_lib", "2.0.0"

        Dir.cd(tmp_path) do
          Dir.mkdir_p("cdx_project/lib/cdx_lib")

          File.write "cdx_project/shard.yml", {
            name: "cdx_project", version: "0.2.0",
            dependencies: {cdx_lib: {git: git_url(:cdx_lib)}},
          }.to_yaml

          File.write "cdx_project/shard.lock", YAML.dump({
            version: Lock::CURRENT_VERSION,
            shards:  {cdx_lib: {git: git_url(:cdx_lib), version: "2.0.0"}},
          })

          File.write "cdx_project/lib/cdx_lib/shard.yml", {
            name: "cdx_lib", version: "2.0.0",
          }.to_yaml

          File.write "cdx_project/lib/.shards.info", YAML.dump({
            version: "1.0",
            shards:  {cdx_lib: {git: git_url(:cdx_lib), version: "2.0.0"}},
          })

          cmd = Commands::SBOM.new("cdx_project")
          cmd.run("cyclonedx", "cdx_project/test-output.cdx.json", false)

          File.exists?("cdx_project/test-output.cdx.json").should be_true
          json = JSON.parse(File.read("cdx_project/test-output.cdx.json"))

          json["bomFormat"].should eq("CycloneDX")
          json["specVersion"].should eq("1.6")
          json["version"].should eq(1)

          json["metadata"]["component"]["name"].should eq("cdx_project")
          json["metadata"]["component"]["version"].should eq("0.2.0")

          components = json["components"].as_a
          components.size.should eq(1)
          components.first["name"].should eq("cdx_lib")
          components.first["version"].should eq("2.0.0")
          components.first["type"].should eq("library")
        end
      end

      it "handles path dependencies with NOASSERTION" do
        create_path_repository "local_dep", "0.5.0"

        Dir.cd(tmp_path) do
          Dir.mkdir_p("path_project/lib/local_dep")

          File.write "path_project/shard.yml", {
            name: "path_project", version: "0.1.0",
            dependencies: {local_dep: {path: git_path(:local_dep)}},
          }.to_yaml

          File.write "path_project/shard.lock", YAML.dump({
            version: Lock::CURRENT_VERSION,
            shards:  {local_dep: {path: git_path(:local_dep), version: "0.5.0"}},
          })

          File.write "path_project/lib/local_dep/shard.yml", {
            name: "local_dep", version: "0.5.0",
          }.to_yaml

          File.write "path_project/lib/.shards.info", YAML.dump({
            version: "1.0",
            shards:  {local_dep: {path: git_path(:local_dep), version: "0.5.0"}},
          })

          cmd = Commands::SBOM.new("path_project")
          cmd.run("spdx", "path_project/output.spdx.json", false)

          json = JSON.parse(File.read("path_project/output.spdx.json"))
          packages = json["packages"].as_a
          dep = packages.find { |p| p["name"].as_s == "local_dep" }.not_nil!
          dep["downloadLocation"].should eq("NOASSERTION")
          dep["externalRefs"]?.should be_nil
        end
      end

      it "generates unique document namespaces" do
        create_git_repository "uuid_lib", "1.0.0"

        Dir.cd(tmp_path) do
          Dir.mkdir_p("uuid_project/lib/uuid_lib")

          File.write "uuid_project/shard.yml", {
            name: "uuid_project", version: "0.1.0",
            dependencies: {uuid_lib: {git: git_url(:uuid_lib)}},
          }.to_yaml

          File.write "uuid_project/shard.lock", YAML.dump({
            version: Lock::CURRENT_VERSION,
            shards:  {uuid_lib: {git: git_url(:uuid_lib), version: "1.0.0"}},
          })

          File.write "uuid_project/lib/uuid_lib/shard.yml", {
            name: "uuid_lib", version: "1.0.0",
          }.to_yaml

          File.write "uuid_project/lib/.shards.info", YAML.dump({
            version: "1.0",
            shards:  {uuid_lib: {git: git_url(:uuid_lib), version: "1.0.0"}},
          })

          cmd = Commands::SBOM.new("uuid_project")
          cmd.run("spdx", "uuid_project/first.json", false)
          cmd.run("spdx", "uuid_project/second.json", false)

          first = JSON.parse(File.read("uuid_project/first.json"))
          second = JSON.parse(File.read("uuid_project/second.json"))
          first["documentNamespace"].should_not eq(second["documentNamespace"])
        end
      end

      it "uses NOASSERTION for missing license" do
        create_git_repository "nolicense_lib", "1.0.0"

        Dir.cd(tmp_path) do
          Dir.mkdir_p("nolicense_project/lib/nolicense_lib")

          File.write "nolicense_project/shard.yml", {
            name: "nolicense_project", version: "0.1.0",
            dependencies: {nolicense_lib: {git: git_url(:nolicense_lib)}},
          }.to_yaml

          File.write "nolicense_project/shard.lock", YAML.dump({
            version: Lock::CURRENT_VERSION,
            shards:  {nolicense_lib: {git: git_url(:nolicense_lib), version: "1.0.0"}},
          })

          # shard.yml without license field
          File.write "nolicense_project/lib/nolicense_lib/shard.yml", {
            name: "nolicense_lib", version: "1.0.0",
          }.to_yaml

          File.write "nolicense_project/lib/.shards.info", YAML.dump({
            version: "1.0",
            shards:  {nolicense_lib: {git: git_url(:nolicense_lib), version: "1.0.0"}},
          })

          cmd = Commands::SBOM.new("nolicense_project")
          cmd.run("spdx", "nolicense_project/output.json", false)

          json = JSON.parse(File.read("nolicense_project/output.json"))
          packages = json["packages"].as_a
          dep = packages.find { |p| p["name"].as_s == "nolicense_lib" }.not_nil!
          dep["licenseDeclared"].should eq("NOASSERTION")
          dep["licenseConcluded"].should eq("NOASSERTION")
        end
      end

      it "populates SPDX element IDs with only valid characters" do
        create_git_repository "my_lib", "1.0.0"

        Dir.cd(tmp_path) do
          Dir.mkdir_p("spdxid_project/lib/my_lib")

          File.write "spdxid_project/shard.yml", {
            name: "spdxid_project", version: "0.1.0",
            dependencies: {my_lib: {git: git_url(:my_lib)}},
          }.to_yaml

          File.write "spdxid_project/shard.lock", YAML.dump({
            version: Lock::CURRENT_VERSION,
            shards:  {my_lib: {git: git_url(:my_lib), version: "1.0.0"}},
          })

          File.write "spdxid_project/lib/my_lib/shard.yml", {
            name: "my_lib", version: "1.0.0",
          }.to_yaml

          File.write "spdxid_project/lib/.shards.info", YAML.dump({
            version: "1.0",
            shards:  {my_lib: {git: git_url(:my_lib), version: "1.0.0"}},
          })

          cmd = Commands::SBOM.new("spdxid_project")
          cmd.run("spdx", "spdxid_project/output.json", false)

          json = JSON.parse(File.read("spdxid_project/output.json"))
          packages = json["packages"].as_a

          packages.each do |pkg|
            spdx_id = pkg["SPDXID"].as_s
            # SPDX IDs must match [a-zA-Z0-9.-]
            spdx_id.should match(/^SPDXRef-[a-zA-Z0-9.\-]+$/)
          end
        end
      end

      it "includes dependency relationships in SPDX" do
        create_git_repository "dep_a", "1.0.0"
        create_git_repository "dep_b", "1.0.0"
        create_git_release "dep_a", "1.1.0", {
          dependencies: {dep_b: {git: git_url(:dep_b)}},
        }

        Dir.cd(tmp_path) do
          Dir.mkdir_p("rel_project/lib/dep_a")
          Dir.mkdir_p("rel_project/lib/dep_b")

          File.write "rel_project/shard.yml", {
            name: "rel_project", version: "0.1.0",
            dependencies: {dep_a: {git: git_url(:dep_a)}},
          }.to_yaml

          File.write "rel_project/shard.lock", YAML.dump({
            version: Lock::CURRENT_VERSION,
            shards:  {
              dep_a: {git: git_url(:dep_a), version: "1.1.0"},
              dep_b: {git: git_url(:dep_b), version: "1.0.0"},
            },
          })

          File.write "rel_project/lib/dep_a/shard.yml", <<-YAML
          name: dep_a
          version: 1.1.0
          dependencies:
            dep_b:
              git: #{git_url(:dep_b)}
          YAML

          File.write "rel_project/lib/dep_b/shard.yml", {
            name: "dep_b", version: "1.0.0",
          }.to_yaml

          File.write "rel_project/lib/.shards.info", YAML.dump({
            version: "1.0",
            shards:  {
              dep_a: {git: git_url(:dep_a), version: "1.1.0"},
              dep_b: {git: git_url(:dep_b), version: "1.0.0"},
            },
          })

          cmd = Commands::SBOM.new("rel_project")
          cmd.run("spdx", "rel_project/output.json", false)

          json = JSON.parse(File.read("rel_project/output.json"))
          relationships = json["relationships"].as_a

          # Root depends on dep_a
          root_deps = relationships.select { |r|
            r["spdxElementId"].as_s == "SPDXRef-RootPackage" &&
              r["relationshipType"].as_s == "DEPENDS_ON"
          }
          root_deps.map { |r| r["relatedSpdxElement"].as_s }.should contain("SPDXRef-Package-dep-a")

          # dep_a depends on dep_b
          a_deps = relationships.select { |r|
            r["spdxElementId"].as_s == "SPDXRef-Package-dep-a" &&
              r["relationshipType"].as_s == "DEPENDS_ON"
          }
          a_deps.map { |r| r["relatedSpdxElement"].as_s }.should contain("SPDXRef-Package-dep-b")
        end
      end
    end
  end
end
