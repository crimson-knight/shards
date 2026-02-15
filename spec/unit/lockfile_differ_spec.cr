require "./spec_helper"
require "../../src/lockfile_differ"
require "../../src/diff_report"

private def make_package(name, version_str, resolver)
  Shards::Package.new(name, resolver, version(version_str))
end

module Shards
  describe LockfileDiffer do
    describe ".diff" do
      it "detects added dependencies" do
        create_git_repository "new_dep", "1.0.0"
        resolver = GitResolver.new("new_dep", git_url("new_dep"))

        from = [] of Package
        to = [make_package("new_dep", "1.0.0", resolver)]

        changes = LockfileDiffer.diff(from, to)
        changes.size.should eq(1)
        changes[0].status.should eq(LockfileDiffer::Status::Added)
        changes[0].name.should eq("new_dep")
        changes[0].from_version.should be_nil
        changes[0].to_version.should eq("1.0.0")
        changes[0].to_source.should eq(git_url("new_dep"))
        changes[0].to_resolver_key.should eq("git")
      end

      it "detects removed dependencies" do
        create_git_repository "old_dep", "2.0.0"
        resolver = GitResolver.new("old_dep", git_url("old_dep"))

        from = [make_package("old_dep", "2.0.0", resolver)]
        to = [] of Package

        changes = LockfileDiffer.diff(from, to)
        changes.size.should eq(1)
        changes[0].status.should eq(LockfileDiffer::Status::Removed)
        changes[0].name.should eq("old_dep")
        changes[0].from_version.should eq("2.0.0")
        changes[0].to_version.should be_nil
        changes[0].from_source.should eq(git_url("old_dep"))
        changes[0].from_resolver_key.should eq("git")
      end

      it "detects updated versions" do
        create_git_repository "my_lib", "1.0.0", "2.0.0"
        resolver = GitResolver.new("my_lib", git_url("my_lib"))

        from = [make_package("my_lib", "1.0.0", resolver)]
        to = [make_package("my_lib", "2.0.0", resolver)]

        changes = LockfileDiffer.diff(from, to)
        changes.size.should eq(1)
        changes[0].status.should eq(LockfileDiffer::Status::Updated)
        changes[0].name.should eq("my_lib")
        changes[0].from_version.should eq("1.0.0")
        changes[0].to_version.should eq("2.0.0")
      end

      it "detects unchanged dependencies" do
        create_git_repository "stable_lib", "1.0.0"
        resolver = GitResolver.new("stable_lib", git_url("stable_lib"))

        from = [make_package("stable_lib", "1.0.0", resolver)]
        to = [make_package("stable_lib", "1.0.0", resolver)]

        changes = LockfileDiffer.diff(from, to)
        changes.size.should eq(1)
        changes[0].status.should eq(LockfileDiffer::Status::Unchanged)
        changes[0].name.should eq("stable_lib")
        changes[0].from_version.should eq("1.0.0")
        changes[0].to_version.should eq("1.0.0")
      end

      it "detects source URL changes" do
        create_git_repository "moved_lib", "1.0.0"
        old_resolver = GitResolver.new("moved_lib", "https://old-host.example.com/moved_lib.git")
        new_resolver = GitResolver.new("moved_lib", git_url("moved_lib"))

        from = [make_package("moved_lib", "1.0.0", old_resolver)]
        to = [make_package("moved_lib", "1.0.0", new_resolver)]

        changes = LockfileDiffer.diff(from, to)
        changes.size.should eq(1)
        changes[0].status.should eq(LockfileDiffer::Status::Updated)
        changes[0].name.should eq("moved_lib")
        changes[0].from_source.should eq("https://old-host.example.com/moved_lib.git")
        changes[0].to_source.should eq(git_url("moved_lib"))
        # Version stays the same
        changes[0].from_version.should eq("1.0.0")
        changes[0].to_version.should eq("1.0.0")
      end

      it "handles commit-pinned versions" do
        create_git_repository "pinned_lib", "1.0.0"
        resolver = GitResolver.new("pinned_lib", git_url("pinned_lib"))

        from_ver = "1.0.0+git.commit.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        to_ver = "1.0.0+git.commit.bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

        from = [Package.new("pinned_lib", resolver, version(from_ver))]
        to = [Package.new("pinned_lib", resolver, version(to_ver))]

        changes = LockfileDiffer.diff(from, to)
        changes.size.should eq(1)
        changes[0].status.should eq(LockfileDiffer::Status::Updated)
        changes[0].from_version.should eq("1.0.0")
        changes[0].to_version.should eq("1.0.0")
        changes[0].from_commit.should eq("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        changes[0].to_commit.should eq("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
      end

      it "handles empty from (fresh install) - all Added" do
        create_git_repository "dep_a", "1.0.0"
        create_git_repository "dep_b", "2.0.0"
        resolver_a = GitResolver.new("dep_a", git_url("dep_a"))
        resolver_b = GitResolver.new("dep_b", git_url("dep_b"))

        from = [] of Package
        to = [
          make_package("dep_a", "1.0.0", resolver_a),
          make_package("dep_b", "2.0.0", resolver_b),
        ]

        changes = LockfileDiffer.diff(from, to)
        changes.size.should eq(2)
        changes.all? { |c| c.status == LockfileDiffer::Status::Added }.should be_true
      end

      it "handles empty to (all removed) - all Removed" do
        create_git_repository "dep_x", "1.0.0"
        create_git_repository "dep_y", "3.0.0"
        resolver_x = GitResolver.new("dep_x", git_url("dep_x"))
        resolver_y = GitResolver.new("dep_y", git_url("dep_y"))

        from = [
          make_package("dep_x", "1.0.0", resolver_x),
          make_package("dep_y", "3.0.0", resolver_y),
        ]
        to = [] of Package

        changes = LockfileDiffer.diff(from, to)
        changes.size.should eq(2)
        changes.all? { |c| c.status == LockfileDiffer::Status::Removed }.should be_true
      end

      it "sorts changes by status then name" do
        create_git_repository "alpha_add", "1.0.0"
        create_git_repository "beta_remove", "1.0.0"
        create_git_repository "gamma_update", "1.0.0", "2.0.0"
        create_git_repository "delta_unchanged", "1.0.0"
        create_git_repository "epsilon_add", "1.0.0"

        resolver_alpha = GitResolver.new("alpha_add", git_url("alpha_add"))
        resolver_beta = GitResolver.new("beta_remove", git_url("beta_remove"))
        resolver_gamma = GitResolver.new("gamma_update", git_url("gamma_update"))
        resolver_delta = GitResolver.new("delta_unchanged", git_url("delta_unchanged"))
        resolver_epsilon = GitResolver.new("epsilon_add", git_url("epsilon_add"))

        from = [
          make_package("beta_remove", "1.0.0", resolver_beta),
          make_package("gamma_update", "1.0.0", resolver_gamma),
          make_package("delta_unchanged", "1.0.0", resolver_delta),
        ]
        to = [
          make_package("alpha_add", "1.0.0", resolver_alpha),
          make_package("epsilon_add", "1.0.0", resolver_epsilon),
          make_package("gamma_update", "2.0.0", resolver_gamma),
          make_package("delta_unchanged", "1.0.0", resolver_delta),
        ]

        changes = LockfileDiffer.diff(from, to)
        changes.size.should eq(5)

        # Added first (alphabetical): alpha_add, epsilon_add
        changes[0].status.should eq(LockfileDiffer::Status::Added)
        changes[0].name.should eq("alpha_add")
        changes[1].status.should eq(LockfileDiffer::Status::Added)
        changes[1].name.should eq("epsilon_add")

        # Updated next: gamma_update
        changes[2].status.should eq(LockfileDiffer::Status::Updated)
        changes[2].name.should eq("gamma_update")

        # Removed next: beta_remove
        changes[3].status.should eq(LockfileDiffer::Status::Removed)
        changes[3].name.should eq("beta_remove")

        # Unchanged last: delta_unchanged
        changes[4].status.should eq(LockfileDiffer::Status::Unchanged)
        changes[4].name.should eq("delta_unchanged")
      end
    end
  end

  describe DiffReport do
    it "any_changes? returns false for all unchanged" do
      create_git_repository "stable", "1.0.0"
      resolver = GitResolver.new("stable", git_url("stable"))

      from = [make_package("stable", "1.0.0", resolver)]
      to = [make_package("stable", "1.0.0", resolver)]

      changes = LockfileDiffer.diff(from, to)
      report = DiffReport.new(changes)
      report.any_changes?.should be_false
    end

    it "any_changes? returns true when there are changes" do
      create_git_repository "new_thing", "1.0.0"
      resolver = GitResolver.new("new_thing", git_url("new_thing"))

      changes = LockfileDiffer.diff([] of Package, [make_package("new_thing", "1.0.0", resolver)])
      report = DiffReport.new(changes)
      report.any_changes?.should be_true
    end

    it "produces valid JSON output" do
      create_git_repository "added_lib", "1.0.0"
      create_git_repository "removed_lib", "2.0.0"
      resolver_add = GitResolver.new("added_lib", git_url("added_lib"))
      resolver_rm = GitResolver.new("removed_lib", git_url("removed_lib"))

      from = [make_package("removed_lib", "2.0.0", resolver_rm)]
      to = [make_package("added_lib", "1.0.0", resolver_add)]

      changes = LockfileDiffer.diff(from, to)
      report = DiffReport.new(changes, "old-lock", "new-lock")

      io = IO::Memory.new
      report.to_json(io)
      output = io.to_s.strip

      parsed = JSON.parse(output)
      parsed["from"].as_s.should eq("old-lock")
      parsed["to"].as_s.should eq("new-lock")
      parsed["changes"]["added"].as_a.size.should eq(1)
      parsed["changes"]["removed"].as_a.size.should eq(1)
      parsed["changes"]["updated"].as_a.size.should eq(0)
      parsed["summary"]["added"].as_i.should eq(1)
      parsed["summary"]["removed"].as_i.should eq(1)
      parsed["summary"]["updated"].as_i.should eq(0)

      # Verify added entry fields
      added_entry = parsed["changes"]["added"][0]
      added_entry["name"].as_s.should eq("added_lib")
      added_entry["to_version"].as_s.should eq("1.0.0")
      added_entry["from_version"].raw.should be_nil
    end

    it "produces markdown output with table structure" do
      create_git_repository "mk_added", "1.0.0"
      create_git_repository "mk_updated", "1.0.0", "2.0.0"
      resolver_add = GitResolver.new("mk_added", git_url("mk_added"))
      resolver_upd = GitResolver.new("mk_updated", git_url("mk_updated"))

      from = [make_package("mk_updated", "1.0.0", resolver_upd)]
      to = [
        make_package("mk_added", "1.0.0", resolver_add),
        make_package("mk_updated", "2.0.0", resolver_upd),
      ]

      changes = LockfileDiffer.diff(from, to)
      report = DiffReport.new(changes)

      io = IO::Memory.new
      report.to_markdown(io)
      output = io.to_s

      output.should contain("## Dependency Changes")
      output.should contain("| Status | Dependency | Version | Source |")
      output.should contain("|--------|-----------|---------|--------|")
      output.should contain("| Added |")
      output.should contain("mk_added")
      output.should contain("| Updated |")
      output.should contain("mk_updated")
      output.should contain("1.0.0 -> 2.0.0")
      output.should contain("**Summary:**")
      output.should contain("1 added")
      output.should contain("1 updated")
      output.should contain("0 removed")
    end

    it "terminal output includes summary line" do
      create_git_repository "term_dep", "1.0.0"
      resolver = GitResolver.new("term_dep", git_url("term_dep"))

      from = [] of Package
      to = [make_package("term_dep", "1.0.0", resolver)]

      changes = LockfileDiffer.diff(from, to)
      report = DiffReport.new(changes, "before", "after")

      io = IO::Memory.new
      report.to_terminal(io)
      output = io.to_s

      output.should contain("Dependency Changes (from before to after):")
      output.should contain("+ term_dep")
      output.should contain("-> 1.0.0")
      output.should contain("Summary: 1 added, 0 updated, 0 removed")
    end

    it "terminal output is empty for no changes" do
      create_git_repository "no_change", "1.0.0"
      resolver = GitResolver.new("no_change", git_url("no_change"))

      from = [make_package("no_change", "1.0.0", resolver)]
      to = [make_package("no_change", "1.0.0", resolver)]

      changes = LockfileDiffer.diff(from, to)
      report = DiffReport.new(changes)

      io = IO::Memory.new
      report.to_terminal(io)
      io.to_s.should eq("")
    end
  end
end
