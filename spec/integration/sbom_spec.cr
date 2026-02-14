require "./spec_helper"
require "json"

describe "sbom" do
  it "generates SPDX 2.3 JSON by default" do
    metadata = {
      dependencies: {web: "*", orm: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      run "shards sbom"

      File.exists?("test.spdx.json").should be_true
      json = JSON.parse(File.read("test.spdx.json"))

      json["spdxVersion"].should eq("SPDX-2.3")
      json["dataLicense"].should eq("CC0-1.0")
      json["SPDXID"].should eq("SPDXRef-DOCUMENT")
      json["name"].should eq("test-sbom")
      json["documentNamespace"].as_s.should start_with("https://spdx.org/spdxdocs/test-")

      # Creation info
      json["creationInfo"]["creators"].as_a.first.as_s.should start_with("Tool: shards-")
      json["creationInfo"]["licenseListVersion"].should eq("3.25")

      # Packages
      packages = json["packages"].as_a
      names = packages.map { |p| p["name"].as_s }

      # Root package + dependencies
      names.should contain("test")
      names.should contain("web")
      names.should contain("orm")
      names.should contain("pg") # transitive dep of orm

      # Root package details
      root = packages.find { |p| p["SPDXID"].as_s == "SPDXRef-RootPackage" }.not_nil!
      root["name"].should eq("test")
      root["filesAnalyzed"].should eq(false)
      root["copyrightText"].should eq("NOASSERTION")

      # All dependency packages should have download locations
      dep_packages = packages.select { |p| p["SPDXID"].as_s != "SPDXRef-RootPackage" }
      dep_packages.each do |pkg|
        pkg["downloadLocation"].as_s.should_not be_empty
        pkg["versionInfo"].as_s.should_not be_empty
      end
    end
  end

  it "generates SPDX relationships" do
    metadata = {
      dependencies: {web: "*", orm: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      run "shards sbom"

      json = JSON.parse(File.read("test.spdx.json"))
      relationships = json["relationships"].as_a

      # DOCUMENT DESCRIBES root
      describes = relationships.find { |r|
        r["spdxElementId"].as_s == "SPDXRef-DOCUMENT" &&
          r["relationshipType"].as_s == "DESCRIBES"
      }
      describes.should_not be_nil
      describes.not_nil!["relatedSpdxElement"].should eq("SPDXRef-RootPackage")

      # Root DEPENDS_ON direct deps
      root_deps = relationships.select { |r|
        r["spdxElementId"].as_s == "SPDXRef-RootPackage" &&
          r["relationshipType"].as_s == "DEPENDS_ON"
      }
      root_dep_names = root_deps.map { |r| r["relatedSpdxElement"].as_s }
      root_dep_names.should contain("SPDXRef-Package-web")
      root_dep_names.should contain("SPDXRef-Package-orm")

      # orm DEPENDS_ON pg (transitive)
      orm_deps = relationships.select { |r|
        r["spdxElementId"].as_s == "SPDXRef-Package-orm" &&
          r["relationshipType"].as_s == "DEPENDS_ON"
      }
      orm_dep_names = orm_deps.map { |r| r["relatedSpdxElement"].as_s }
      orm_dep_names.should contain("SPDXRef-Package-pg")
    end
  end

  it "generates CycloneDX 1.6 JSON" do
    metadata = {
      dependencies: {web: "*", orm: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      run "shards sbom --format=cyclonedx"

      File.exists?("test.cdx.json").should be_true
      json = JSON.parse(File.read("test.cdx.json"))

      json["bomFormat"].should eq("CycloneDX")
      json["specVersion"].should eq("1.6")
      json["version"].should eq(1)

      # Metadata
      json["metadata"]["component"]["type"].should eq("application")
      json["metadata"]["component"]["name"].should eq("test")
      json["metadata"]["component"]["bom-ref"].should eq("test")
      json["metadata"]["tools"]["components"].as_a.first["name"].should eq("shards")

      # Components
      components = json["components"].as_a
      component_names = components.map { |c| c["name"].as_s }
      component_names.should contain("web")
      component_names.should contain("orm")
      component_names.should contain("pg")

      components.each do |comp|
        comp["type"].should eq("library")
        comp["version"].as_s.should_not be_empty
      end

      # Dependencies
      deps = json["dependencies"].as_a
      root_dep = deps.find { |d| d["ref"].as_s == "test" }
      root_dep.should_not be_nil
    end
  end

  it "generates CycloneDX dependency graph" do
    metadata = {
      dependencies: {web: "*", orm: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      run "shards sbom --format=cyclonedx"

      json = JSON.parse(File.read("test.cdx.json"))
      deps = json["dependencies"].as_a

      # Root should depend on web and orm
      root_dep = deps.find { |d| d["ref"].as_s == "test" }.not_nil!
      root_depends_on = root_dep["dependsOn"].as_a.map(&.as_s)
      # Should contain refs for web and orm (could be purls or names)
      root_depends_on.size.should be >= 2
    end
  end

  it "writes to custom output path" do
    metadata = {
      dependencies: {web: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      run "shards sbom --output=custom-sbom.json"

      File.exists?("custom-sbom.json").should be_true
      json = JSON.parse(File.read("custom-sbom.json"))
      json["spdxVersion"].should eq("SPDX-2.3")
    end
  end

  it "writes CycloneDX to custom output path" do
    metadata = {
      dependencies: {web: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      run "shards sbom --format=cyclonedx --output=custom-cdx.json"

      File.exists?("custom-cdx.json").should be_true
      json = JSON.parse(File.read("custom-cdx.json"))
      json["bomFormat"].should eq("CycloneDX")
    end
  end

  it "fails without lock file" do
    metadata = {
      dependencies: {web: "*"},
    }
    with_shard(metadata) do
      ex = expect_raises(FailedCommand) { run "shards sbom --no-color" }
      ex.stdout.should contain("Missing shard.lock")
    end
  end

  it "fails with unknown format" do
    metadata = {
      dependencies: {web: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      ex = expect_raises(FailedCommand) { run "shards sbom --format=unknown --no-color" }
      ex.stdout.should contain("Unknown SBOM format")
    end
  end

  it "handles dependencies with no transitive deps" do
    metadata = {
      dependencies: {web: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      run "shards sbom"

      json = JSON.parse(File.read("test.spdx.json"))
      packages = json["packages"].as_a
      names = packages.map { |p| p["name"].as_s }
      names.should contain("web")
      names.size.should eq(2) # root + web
    end
  end

  it "generates valid SPDX element IDs" do
    metadata = {
      dependencies: {web: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      run "shards sbom"

      json = JSON.parse(File.read("test.spdx.json"))
      packages = json["packages"].as_a
      packages.each do |pkg|
        spdx_id = pkg["SPDXID"].as_s
        spdx_id.should match(/^SPDXRef-[a-zA-Z0-9.\-]+$/)
      end

      relationships = json["relationships"].as_a
      relationships.each do |rel|
        rel["spdxElementId"].as_s.should match(/^SPDXRef-[a-zA-Z0-9.\-]+$/)
        rel["relatedSpdxElement"].as_s.should match(/^SPDXRef-[a-zA-Z0-9.\-]+$/)
      end
    end
  end

  it "generates unique SPDX document namespace" do
    metadata = {
      dependencies: {web: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      run "shards sbom --output=first.json"
      run "shards sbom --output=second.json"

      first = JSON.parse(File.read("first.json"))
      second = JSON.parse(File.read("second.json"))

      first["documentNamespace"].should_not eq(second["documentNamespace"])
    end
  end

  it "includes path dependencies with NOASSERTION download" do
    metadata = {
      dependencies: {foo: {path: rel_path(:foo)}},
    }
    with_shard(metadata) do
      run "shards install"
      run "shards sbom"

      json = JSON.parse(File.read("test.spdx.json"))
      packages = json["packages"].as_a
      foo_pkg = packages.find { |p| p["name"].as_s == "foo" }
      foo_pkg.should_not be_nil
      foo_pkg.not_nil!["downloadLocation"].should eq("NOASSERTION")
    end
  end

  it "path dependencies have no purl in SPDX" do
    metadata = {
      dependencies: {foo: {path: rel_path(:foo)}},
    }
    with_shard(metadata) do
      run "shards install"
      run "shards sbom"

      json = JSON.parse(File.read("test.spdx.json"))
      packages = json["packages"].as_a
      foo_pkg = packages.find { |p| p["name"].as_s == "foo" }.not_nil!
      foo_pkg["externalRefs"]?.should be_nil
    end
  end

  it "path dependencies have no purl in CycloneDX" do
    metadata = {
      dependencies: {foo: {path: rel_path(:foo)}},
    }
    with_shard(metadata) do
      run "shards install"
      run "shards sbom --format=cyclonedx"

      json = JSON.parse(File.read("test.cdx.json"))
      components = json["components"].as_a
      foo_comp = components.find { |c| c["name"].as_s == "foo" }.not_nil!
      foo_comp["purl"]?.should be_nil
    end
  end

  it "SPDX output has valid JSON structure" do
    metadata = {
      dependencies: {web: "*", orm: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      run "shards sbom"

      content = File.read("test.spdx.json")
      # Should not raise
      json = JSON.parse(content)

      # Required SPDX fields
      json["spdxVersion"]?.should_not be_nil
      json["dataLicense"]?.should_not be_nil
      json["SPDXID"]?.should_not be_nil
      json["name"]?.should_not be_nil
      json["documentNamespace"]?.should_not be_nil
      json["creationInfo"]?.should_not be_nil
      json["packages"]?.should_not be_nil
      json["relationships"]?.should_not be_nil
    end
  end

  it "CycloneDX output has valid JSON structure" do
    metadata = {
      dependencies: {web: "*", orm: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      run "shards sbom --format=cyclonedx"

      content = File.read("test.cdx.json")
      json = JSON.parse(content)

      # Required CycloneDX fields
      json["bomFormat"]?.should_not be_nil
      json["specVersion"]?.should_not be_nil
      json["version"]?.should_not be_nil
      json["metadata"]?.should_not be_nil
      json["components"]?.should_not be_nil
      json["dependencies"]?.should_not be_nil
    end
  end
end
