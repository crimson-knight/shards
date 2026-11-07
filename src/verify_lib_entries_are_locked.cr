require "./checksum"
require "./errors"
require "./helpers"

module Shards
  # `--frozen` promises that the install directory holds what the lock says and
  # nothing else. Every other check looks at an entry a run knows about; this
  # one fails on an entry the lock does not pin however it got there, on this
  # run or an earlier one.
  class VerifyLibEntriesAreLocked
    def initialize(@install_path : String, @list_of_locked_names : Array(String))
    end

    def perform : Nil
      return if inside_an_installed_copy?

      list_of_unlocked_names = Helpers.list_install_entries(@install_path).to_a - @list_of_locked_names
      return if list_of_unlocked_names.empty?

      raise UnlockedLibEntry.new(list_of_unlocked_names.sort.map { |entry_name| File.join(@install_path, entry_name) })
    end

    # A nested install runs inside an installed copy, whose `lib` is the link
    # back to the project's install directory. Its own lock need not list the
    # copy it runs in, and the project's run checks that directory itself.
    private def inside_an_installed_copy? : Bool
      File.symlink?(@install_path) && File.readlink(@install_path) == Checksum::INSTALLED_LIB_LINK_TARGET
    end
  end
end
