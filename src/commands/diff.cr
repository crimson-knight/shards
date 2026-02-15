require "./command"
require "../lockfile_differ"
require "../diff_report"

module Shards
  module Commands
    class Diff < Command
      @from_ref : String = "HEAD"
      @to_ref : String = "current"
      @format : String = "terminal"

      def run(args : Array(String))
        parse_args(args)

        from_packages = resolve_ref(@from_ref)
        to_packages = resolve_ref(@to_ref)

        changes = LockfileDiffer.diff(from_packages, to_packages)

        report = DiffReport.new(changes, from_label: @from_ref, to_label: @to_ref)

        if report.any_changes?
          case @format
          when "terminal" then report.to_terminal
          when "json"     then report.to_json
          when "markdown" then report.to_markdown
          else
            raise Error.new("Unknown format: #{@format}. Use: terminal, json, markdown")
          end
        else
          Log.info { "No dependency changes between #{@from_ref} and #{@to_ref}." }
        end
      end

      private def parse_args(args : Array(String))
        args.each do |arg|
          case arg
          when .starts_with?("--from=")   then @from_ref = arg.split("=", 2).last
          when .starts_with?("--to=")     then @to_ref = arg.split("=", 2).last
          when .starts_with?("--format=") then @format = arg.split("=", 2).last
          end
        end
      end

      private def resolve_ref(ref : String) : Array(Package)
        case ref
        when "current"
          if lockfile?
            locks.shards
          else
            [] of Package
          end
        else
          if File.exists?(ref) && ref.ends_with?(".lock")
            Shards::Lock.from_file(ref).shards
          else
            read_lockfile_from_git_ref(ref)
          end
        end
      end

      private def read_lockfile_from_git_ref(ref : String) : Array(Package)
        output = IO::Memory.new
        error = IO::Memory.new
        status = Process.run(
          "git", ["show", "#{ref}:#{LOCK_FILENAME}"],
          output: output, error: error, chdir: @path
        )

        unless status.success?
          raise Error.new("Could not read #{LOCK_FILENAME} from git ref '#{ref}': #{error.to_s.strip}")
        end

        Shards::Lock.from_yaml(output.to_s).shards
      end
    end
  end
end
