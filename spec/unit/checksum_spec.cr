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

      it "starts with sha256: prefix" do
        path = File.tempname("checksum", "test")
        Dir.mkdir_p(path)
        begin
          File.write(File.join(path, "file.txt"), "content")
          result = Checksum.compute(path)
          result.should start_with("sha256:")
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

      it "excludes lib directory at top level" do
        path = File.tempname("checksum", "test")
        Dir.mkdir_p(path)
        begin
          File.write(File.join(path, "file.txt"), "hello")
          checksum1 = Checksum.compute(path)

          Dir.mkdir_p(File.join(path, "lib", "some_dep"))
          File.write(File.join(path, "lib", "some_dep", "main.cr"), "module SomeDep; end")
          checksum2 = Checksum.compute(path)

          checksum1.should eq(checksum2)
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
          result1.should start_with("sha256:")
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
          result.should start_with("sha256:")

          # Compute again to ensure determinism with nested structure
          result2 = Checksum.compute(path)
          result.should eq(result2)
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
          fake_checksum = "sha256:0000000000000000000000000000000000000000000000000000000000000000"
          Checksum.verify(path, fake_checksum).should be_false
        ensure
          Shards::Helpers.rm_rf(path)
        end
      end
    end
  end
end
