require "./spec_helper"
require "../../src/checksum"

module Shards
  describe Checksum do
    describe ".compute" do
      it "produces a deterministic checksum" do
        path = File.tempname("checksum", "test")
        Dir.mkdir_p(path)
        begin
          File.write(File.join(path, "file.txt"), "hello world")
          result1 = Checksum.compute(path)
          result2 = Checksum.compute(path)
          result1.should eq(result2)
        ensure
          Shards::Helpers.rm_rf(path)
        end
      end

      it "starts with the sha256-v2: prefix" do
        path = File.tempname("checksum", "test")
        Dir.mkdir_p(path)
        begin
          File.write(File.join(path, "file.txt"), "content")
          result = Checksum.compute(path)
          result.should start_with("sha256-v2:")
        ensure
          Shards::Helpers.rm_rf(path)
        end
      end

      it "detects file content changes" do
        path = File.tempname("checksum", "test")
        Dir.mkdir_p(path)
        begin
          File.write(File.join(path, "file.txt"), "original")
          checksum1 = Checksum.compute(path)

          File.write(File.join(path, "file.txt"), "modified")
          checksum2 = Checksum.compute(path)

          checksum1.should_not eq(checksum2)
        ensure
          Shards::Helpers.rm_rf(path)
        end
      end

      it "detects file addition" do
        path = File.tempname("checksum", "test")
        Dir.mkdir_p(path)
        begin
          File.write(File.join(path, "file.txt"), "hello")
          checksum1 = Checksum.compute(path)

          File.write(File.join(path, "extra.txt"), "extra")
          checksum2 = Checksum.compute(path)

          checksum1.should_not eq(checksum2)
        ensure
          Shards::Helpers.rm_rf(path)
        end
      end

      it "detects file deletion" do
        path = File.tempname("checksum", "test")
        Dir.mkdir_p(path)
        begin
          File.write(File.join(path, "a.txt"), "aaa")
          File.write(File.join(path, "b.txt"), "bbb")
          checksum1 = Checksum.compute(path)

          File.delete(File.join(path, "b.txt"))
          checksum2 = Checksum.compute(path)

          checksum1.should_not eq(checksum2)
        ensure
          Shards::Helpers.rm_rf(path)
        end
      end

      it "detects file rename" do
        path = File.tempname("checksum", "test")
        Dir.mkdir_p(path)
        begin
          File.write(File.join(path, "original.txt"), "content")
          checksum1 = Checksum.compute(path)

          File.rename(File.join(path, "original.txt"), File.join(path, "renamed.txt"))
          checksum2 = Checksum.compute(path)

          checksum1.should_not eq(checksum2)
        ensure
          Shards::Helpers.rm_rf(path)
        end
      end

      it "is order independent (files are sorted)" do
        path1 = File.tempname("checksum", "test1")
        Dir.mkdir_p(path1)
        path2 = File.tempname("checksum", "test2")
        Dir.mkdir_p(path2)
        begin
          # Create files in different orders in two directories
          File.write(File.join(path1, "a.txt"), "aaa")
          File.write(File.join(path1, "b.txt"), "bbb")
          File.write(File.join(path1, "c.txt"), "ccc")

          File.write(File.join(path2, "c.txt"), "ccc")
          File.write(File.join(path2, "a.txt"), "aaa")
          File.write(File.join(path2, "b.txt"), "bbb")

          checksum1 = Checksum.compute(path1)
          checksum2 = Checksum.compute(path2)

          checksum1.should eq(checksum2)
        ensure
          Shards::Helpers.rm_rf(path1)
          Shards::Helpers.rm_rf(path2)
        end
      end

      it "excludes .git directory" do
        path = File.tempname("checksum", "test")
        Dir.mkdir_p(path)
        begin
          File.write(File.join(path, "file.txt"), "hello")
          checksum1 = Checksum.compute(path)

          Dir.mkdir_p(File.join(path, ".git", "objects"))
          File.write(File.join(path, ".git", "HEAD"), "ref: refs/heads/master")
          File.write(File.join(path, ".git", "objects", "abc"), "object data")
          checksum2 = Checksum.compute(path)

          checksum1.should eq(checksum2)
        ensure
          Shards::Helpers.rm_rf(path)
        end
      end

      it "excludes the lib link Minecart writes to the project install path" do
        path = File.tempname("checksum", "test")
        Dir.mkdir_p(path)
        begin
          File.write(File.join(path, "file.txt"), "hello")
          checksum1 = Checksum.compute(path)

          File.symlink(Checksum::INSTALLED_LIB_LINK_TARGET, File.join(path, "lib"))
          Checksum.compute(path).should eq(checksum1)
        ensure
          Shards::Helpers.rm_rf(path)
        end
      end

      it "hashes a shipped top-level lib link to any other target" do
        path = File.tempname("checksum", "test")
        Dir.mkdir_p(path)
        begin
          File.write(File.join(path, "file.txt"), "hello")
          checksum1 = Checksum.compute(path)

          File.symlink("/nonexistent/elsewhere", File.join(path, "lib"))
          Checksum.compute(path).should_not eq(checksum1)
        ensure
          Shards::Helpers.rm_rf(path)
        end
      end

      it "hashes a real top-level lib directory that ships with the shard" do
        path = File.tempname("checksum", "test")
        Dir.mkdir_p(path)
        begin
          File.write(File.join(path, "file.txt"), "hello")
          checksum1 = Checksum.compute(path)

          Dir.mkdir_p(File.join(path, "lib"))
          File.write(File.join(path, "lib", "payload.sh"), "echo original")
          checksum2 = Checksum.compute(path)
          checksum2.should_not eq(checksum1)

          File.write(File.join(path, "lib", "payload.sh"), "echo replaced")
          Checksum.compute(path).should_not eq(checksum2)
        ensure
          Shards::Helpers.rm_rf(path)
        end
      end

      it "hashes a symlink to an absolute path by its link text and never follows it" do
        path = File.tempname("checksum", "test")
        outside = File.tempname("checksum", "outside")
        Dir.mkdir_p(path)
        Dir.mkdir_p(outside)
        begin
          File.write(File.join(outside, "payload.sh"), "echo outside")
          File.symlink(outside, File.join(path, "vendor"))
          checksum1 = Checksum.compute(path)

          File.write(File.join(outside, "payload.sh"), "echo changed outside")
          Checksum.compute(path).should eq(checksum1)

          File.delete(File.join(path, "vendor"))
          File.symlink(File.join(outside, "elsewhere"), File.join(path, "vendor"))
          Checksum.compute(path).should_not eq(checksum1)
        ensure
          Shards::Helpers.rm_rf(path)
          Shards::Helpers.rm_rf(outside)
        end
      end

      it "hashes any other symlinked directory by its link text" do
        path = File.tempname("checksum", "test")
        Dir.mkdir_p(File.join(path, "first"))
        Dir.mkdir_p(File.join(path, "second"))
        begin
          File.symlink("first", File.join(path, "current"))
          checksum1 = Checksum.compute(path)

          File.delete(File.join(path, "current"))
          File.symlink("second", File.join(path, "current"))
          Checksum.compute(path).should_not eq(checksum1)
        ensure
          Shards::Helpers.rm_rf(path)
        end
      end

      it "does not crash on a broken symlink and hashes its link text" do
        path = File.tempname("checksum", "test")
        Dir.mkdir_p(path)
        begin
          File.write(File.join(path, "file.txt"), "content")
          File.symlink("does/not/exist", File.join(path, "dangling"))
          checksum1 = Checksum.compute(path)
          checksum1.should start_with("sha256-v2:")

          File.delete(File.join(path, "dangling"))
          File.symlink("somewhere/else", File.join(path, "dangling"))
          Checksum.compute(path).should_not eq(checksum1)
        ensure
          Shards::Helpers.rm_rf(path)
        end
      end

      it "distinguishes a file from a symlink to identical bytes" do
        path = File.tempname("checksum", "test")
        linked = File.tempname("checksum", "test")
        Dir.mkdir_p(path)
        Dir.mkdir_p(linked)
        begin
          File.write(File.join(linked, "real.txt"), "shared content")
          File.write(File.join(path, "copy.txt"), "shared content")
          copy_checksum = Checksum.compute(path)

          File.delete(File.join(path, "copy.txt"))
          File.symlink(File.join(linked, "real.txt"), File.join(path, "copy.txt"))
          Checksum.compute(path).should_not eq(copy_checksum)
        ensure
          Shards::Helpers.rm_rf(path)
          Shards::Helpers.rm_rf(linked)
        end
      end

      it "binds the executable mode of each file" do
        path = File.tempname("checksum", "test")
        Dir.mkdir_p(path)
        begin
          script = File.join(path, "build.sh")
          File.write(script, "echo build")
          File.chmod(script, 0o644)
          regular_checksum = Checksum.compute(path)

          File.chmod(script, 0o755)
          Checksum.compute(path).should_not eq(regular_checksum)
        ensure
          Shards::Helpers.rm_rf(path)
        end
      end

      it "produces consistent hash for empty directory" do
        path = File.tempname("checksum", "test")
        Dir.mkdir_p(path)
        begin
          result1 = Checksum.compute(path)
          result2 = Checksum.compute(path)
          result1.should eq(result2)
          result1.should start_with("sha256-v2:")
        ensure
          Shards::Helpers.rm_rf(path)
        end
      end

      it "handles deeply nested directories" do
        path = File.tempname("checksum", "test")
        Dir.mkdir_p(path)
        begin
          nested = File.join(path, "a", "b", "c", "d", "e")
          Dir.mkdir_p(nested)
          File.write(File.join(nested, "deep.txt"), "deep content")
          File.write(File.join(path, "top.txt"), "top content")

          result = Checksum.compute(path)
          result.should start_with("sha256-v2:")

          # Compute again to ensure determinism with nested structure
          result2 = Checksum.compute(path)
          result.should eq(result2)
        ensure
          Shards::Helpers.rm_rf(path)
        end
      end
    end

    describe ".compute_legacy_sha256" do
      # The digest Minecart 2025.11.25.8 wrote as `sha256:`. The expected value
      # was computed by that release's Checksum.compute over this same tree, so
      # existing lock entries keep verifying.
      it "matches the digest Minecart 2025.11.25.8 recorded" do
        path = File.tempname("checksum", "legacy")
        begin
          Dir.mkdir_p(File.join(path, "src", "nested"))
          Dir.mkdir_p(File.join(path, "lib", "inner"))
          Dir.mkdir_p(File.join(path, "outside"))
          File.write(File.join(path, "src", "a.cr"), "puts 1\n")
          File.write(File.join(path, "src", "nested", "b.cr"), "puts 2\n")
          File.write(File.join(path, "lib", "inner", "skipped.cr"), "skipped\n")
          File.write(File.join(path, "outside", "real.txt"), "linked content\n")
          File.write(File.join(path, "run.sh"), "echo hi\n")
          File.chmod(File.join(path, "run.sh"), 0o755)
          File.symlink("outside", File.join(path, "dirlink"))
          File.symlink("outside/real.txt", File.join(path, "filelink"))
          File.symlink("does/not/exist", File.join(path, "dangling"))

          expected = "sha256:a6bc346dfc626c85b1249a5c5b9f2278290a668d1f789f3283e59df1e7c55da4"
          Checksum.compute_legacy_sha256(path).should eq(expected)
          Checksum.verify(path, expected).should be_true
          Checksum.compute(path).should start_with("sha256-v2:")
        ensure
          Shards::Helpers.rm_rf(path)
        end
      end
    end

    describe ".verify" do
      it "returns true for matching checksum" do
        path = File.tempname("checksum", "test")
        Dir.mkdir_p(path)
        begin
          File.write(File.join(path, "file.txt"), "test content")
          expected = Checksum.compute(path)
          Checksum.verify(path, expected).should be_true
        ensure
          Shards::Helpers.rm_rf(path)
        end
      end

      it "returns false for mismatched checksum" do
        path = File.tempname("checksum", "test")
        Dir.mkdir_p(path)
        begin
          File.write(File.join(path, "file.txt"), "test content")
          fake_checksum = "sha256-v2:0000000000000000000000000000000000000000000000000000000000000000"
          Checksum.verify(path, fake_checksum).should be_false
        ensure
          Shards::Helpers.rm_rf(path)
        end
      end
    end
  end
end
