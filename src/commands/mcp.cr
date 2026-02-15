require "./command"
require "../mcp_manager"

module Shards
  module Commands
    class MCP < Command
      def run(args : Array(String))
        subcommand = args[0]? || "status"
        remaining = args.size > 1 ? args[1..] : [] of String

        case subcommand
        when "status"
          show_status
        when "start"
          manager.start(remaining[0]?)
        when "stop"
          manager.stop(remaining[0]?)
        when "restart"
          manager.restart(remaining[0]?)
        when "logs"
          raise Error.new("Usage: shards mcp logs <server_name> [--no-follow] [--lines=N]") if remaining.empty?
          server_name = remaining.reject(&.starts_with?("--")).first? ||
                        raise Error.new("Usage: shards mcp logs <server_name>")
          follow = !remaining.includes?("--no-follow")
          lines = 20
          remaining.each do |arg|
            if arg.starts_with?("--lines=")
              lines = arg.split("=", 2).last.to_i
            end
          end
          manager.logs(server_name, follow, lines)
        else
          raise Error.new("Unknown mcp subcommand: #{subcommand}. Use: status, start, stop, restart, logs")
        end
      end

      private def show_status
        entries = manager.status

        if entries.empty?
          Log.info { "No MCP servers configured." }
          return
        end

        puts "MCP Servers:"
        entries.each do |info|
          if info.running
            uptime_str = info.started_at ? format_uptime(Time.utc - info.started_at.not_nil!) : "unknown"
            puts "  #{info.name}  [running]  #{info.transport}  PID #{info.pid}  uptime #{uptime_str}"
          else
            puts "  #{info.name}  [stopped]  #{info.transport}"
          end
        end
      end

      private def format_uptime(span : Time::Span) : String
        total_seconds = span.total_seconds.to_i
        if total_seconds >= 3600
          hours = total_seconds // 3600
          minutes = (total_seconds % 3600) // 60
          "#{hours}h #{minutes}m"
        elsif total_seconds >= 60
          minutes = total_seconds // 60
          seconds = total_seconds % 60
          "#{minutes}m #{seconds}s"
        else
          "#{total_seconds}s"
        end
      end

      @manager : MCPManager?

      private def manager : MCPManager
        @manager ||= MCPManager.new(path)
      end
    end
  end
end
