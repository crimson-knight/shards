require "./spec_helper"
require "../../src/verify_lib_entries_are_locked"

private def with_install_directory(&)
  directory = File.tempname("minecart-lib-entries")
  Dir.mkdir_p(directory)
  begin
    yield directory
  ensure
    Shards::Helpers.rm_rf(directory)
  end
end

module Shards
  describe VerifyLibEntriesAreLocked do
    it "passes when every entry is locked or is install state" do
      with_install_directory do |directory|
        Dir.mkdir(File.join(directory, "web"))
        File.touch(File.join(directory, ".shards.info"))
        File.touch(File.join(directory, POSTINSTALL_INFO_FILENAME))

        VerifyLibEntriesAreLocked.new(directory, ["web"]).perform
      end
    end

    it "names every entry the lock does not pin" do
      with_install_directory do |directory|
        Dir.mkdir(File.join(directory, "web"))
        Dir.mkdir(File.join(directory, "stray"))
        File.touch(File.join(directory, "other.cr"))

        ex = expect_raises(UnlockedLibEntry) { VerifyLibEntriesAreLocked.new(directory, ["web"]).perform }
        ex.message.to_s.should contain(File.join(directory, "stray"))
        ex.message.to_s.should contain(File.join(directory, "other.cr"))
      end
    end

    it "passes when the install directory does not exist yet" do
      VerifyLibEntriesAreLocked.new(File.tempname("minecart-no-lib"), ["web"]).perform
    end

    # A nested install runs inside an installed copy, where `lib` is the link
    # back to the project's install directory; the project's own run checks it.
    it "leaves the install directory alone when it is an installed copy's lib link" do
      with_install_directory do |directory|
        Dir.mkdir(File.join(directory, "stray"))
        copy = File.join(directory, "owner")
        Dir.mkdir(copy)
        File.symlink("..", File.join(copy, "lib"))

        VerifyLibEntriesAreLocked.new(File.join(copy, "lib"), [] of String).perform
      end
    end
  end

  describe Helpers do
    describe ".rm_rf!" do
      it "removes a read-only directory and what it holds" do
        with_install_directory do |directory|
          entry = File.join(directory, "entry")
          Dir.mkdir(entry)
          File.touch(File.join(entry, "file.cr"))
          File.chmod(entry, 0o555)

          Helpers.rm_rf!(entry)
          File.exists?(entry).should be_false
        end
      end

      it "removes a symlink without following it or changing its target" do
        with_install_directory do |directory|
          target = File.join(directory, "target")
          Dir.mkdir(target)
          File.chmod(target, 0o555)
          link = File.join(directory, "link")
          File.symlink(target, link)

          Helpers.rm_rf!(link)
          File.symlink?(link).should be_false
          Dir.exists?(target).should be_true
          File.info(target).permissions.includes?(File::Permissions::OwnerWrite).should be_false
          File.chmod(target, 0o755)
        end
      end

      it "raises naming a path it could not remove" do
        with_install_directory do |directory|
          parent = File.join(directory, "parent")
          entry = File.join(parent, "entry")
          Dir.mkdir_p(entry)
          File.chmod(parent, 0o555)

          begin
            ex = expect_raises(PathNotRemoved) { Helpers.rm_rf!(entry) }
            ex.message.to_s.should contain(entry)
          ensure
            File.chmod(parent, 0o755)
          end
        end
      end

      it "does nothing for a path that is already gone" do
        Helpers.rm_rf!(File.tempname("minecart-gone"))
      end
    end
  end
end
