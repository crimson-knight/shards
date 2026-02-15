require "json"

module Shards
  class MCPManager
    Log = ::Log.for("shards.mcp")

    MCP_SHARDS_CONFIG = ".mcp-shards.json"
    RUNTIME_DIR       = ".shards/mcp"
    STATE_FILE        = "servers.json"
    BIN_DIR           = "bin"

    struct ServerConfig
      getter name : String
      getter command : String?
      getter args : Array(String)
      getter crystal_main : String?
      getter transport : String
      getter env : Hash(String, String)

      def initialize(@name, @command, @args, @crystal_main, @transport, @env)
      end
    end

    struct ServerState
      include JSON::Serializable

      property name : String
      property pid : Int64
      property transport : String
      property port : Int32?
      property log_file : String
      property command : String
      property args : Array(String)
      property started_at : String

      def initialize(@name, @pid, @transport, @port, @log_file, @command, @args, @started_at)
      end
    end

    struct StateFile
      include JSON::Serializable

      property version : String = "1.0"
      property servers : Hash(String, ServerState) = {} of String => ServerState

      def initialize
      end
    end

    getter path : String

    def initialize(@path : String)
    end

    def start(name : String? = nil)
      configs = load_configs
      raise Error.new("No MCP servers configured. Ensure .mcp-shards.json exists.") if configs.empty?

      targets = resolve_targets(configs, name)
      state = load_state

      targets.each do |config|
        key = sanitize_name(config.name)
        if existing = state.servers[key]?
          if process_alive?(existing.pid)
            Log.info { "Server #{config.name} is already running (PID #{existing.pid})" }
            next
          end
          # Stale entry, clean up
          state.servers.delete(key)
        end

        start_server(config, state)
      end

      save_state(state)
    end

    def stop(name : String? = nil)
      configs = load_configs
      raise Error.new("No MCP servers configured. Ensure .mcp-shards.json exists.") if configs.empty?

      targets = resolve_targets(configs, name)
      state = load_state

      targets.each do |config|
        key = sanitize_name(config.name)
        entry = state.servers[key]?
        unless entry
          Log.info { "Server #{config.name} is not running" }
          next
        end

        stop_server(entry)
        state.servers.delete(key)
      end

      save_state(state)
    end

    def restart(name : String? = nil)
      configs = load_configs
      raise Error.new("No MCP servers configured. Ensure .mcp-shards.json exists.") if configs.empty?

      targets = resolve_targets(configs, name)
      state = load_state

      targets.each do |config|
        key = sanitize_name(config.name)
        if entry = state.servers[key]?
          stop_server(entry)
          state.servers.delete(key)
        end

        start_server(config, state)
      end

      save_state(state)
    end

    struct ServerStatusInfo
      getter name : String
      getter running : Bool
      getter pid : Int64?
      getter transport : String
      getter started_at : Time?

      def initialize(@name, @running, @pid, @transport, @started_at)
      end
    end

    def status : Array(ServerStatusInfo)
      configs = load_configs
      return [] of ServerStatusInfo if configs.empty?

      state = load_state
      stale_cleaned = false

      results = configs.map do |config|
        key = sanitize_name(config.name)
        if entry = state.servers[key]?
          if process_alive?(entry.pid)
            started = Time.parse_iso8601(entry.started_at) rescue nil
            ServerStatusInfo.new(config.name, true, entry.pid, entry.transport, started)
          else
            state.servers.delete(key)
            stale_cleaned = true
            ServerStatusInfo.new(config.name, false, nil, config.transport, nil)
          end
        else
          ServerStatusInfo.new(config.name, false, nil, config.transport, nil)
        end
      end

      save_state(state) if stale_cleaned
      results
    end

    def logs(name : String, follow : Bool = true, lines : Int32 = 20)
      configs = load_configs
      raise Error.new("No MCP servers configured.") if configs.empty?

      config = resolve_single(configs, name)
      key = sanitize_name(config.name)
      log_path = File.join(path, RUNTIME_DIR, "#{key}.log")

      unless File.exists?(log_path)
        raise Error.new("No log file found for #{config.name}. Has the server been started?")
      end

      print_last_lines(log_path, lines)

      if follow
        last_size = File.size(log_path)
        loop do
          sleep 0.5.seconds
          current_size = File.size(log_path)
          if current_size > last_size
            File.open(log_path) do |f|
              f.seek(last_size)
              while line = f.gets
                puts line
              end
            end
            last_size = current_size
          end
        end
      end
    end

    # --- Config loading ---

    def load_configs : Array(ServerConfig)
      config_path = File.join(path, MCP_SHARDS_CONFIG)
      return [] of ServerConfig unless File.exists?(config_path)

      json = JSON.parse(File.read(config_path))
      servers = json["mcpServers"]?.try(&.as_h?) || return [] of ServerConfig

      servers.compact_map do |name, entry|
        h = entry.as_h? || next

        command = h["command"]?.try(&.as_s?)
        crystal_main = h["crystal_main"]?.try(&.as_s?)
        next unless command || crystal_main

        args = h["args"]?.try(&.as_a?.try(&.map(&.as_s))) || [] of String

        transport = if h["transport"]?.try(&.as_s?) == "sse" || h["url"]?
                      "sse"
                    else
                      "stdio"
                    end

        env = {} of String => String
        if env_hash = h["env"]?.try(&.as_h?)
          env_hash.each do |k, v|
            env[k] = v.as_s? || v.to_s
          end
        end

        ServerConfig.new(name, command, args, crystal_main, transport, env)
      end
    end

    # --- State persistence ---

    private def state_path : String
      File.join(path, RUNTIME_DIR, STATE_FILE)
    end

    private def load_state : StateFile
      return StateFile.new unless File.exists?(state_path)
      StateFile.from_json(File.read(state_path))
    rescue JSON::ParseException
      StateFile.new
    end

    private def save_state(state : StateFile)
      dir = File.join(path, RUNTIME_DIR)
      Dir.mkdir_p(dir) unless Dir.exists?(dir)
      File.write(state_path, state.to_pretty_json + "\n")
    end

    # --- Process lifecycle ---

    private def start_server(config : ServerConfig, state : StateFile)
      key = sanitize_name(config.name)
      runtime_dir = File.join(path, RUNTIME_DIR)
      Dir.mkdir_p(runtime_dir) unless Dir.exists?(runtime_dir)

      # Determine command
      cmd, cmd_args = resolve_command(config)

      # Truncate log file
      log_path = File.join(runtime_dir, "#{key}.log")
      log_file = File.open(log_path, "w")

      Log.info { "Starting #{config.name}: #{cmd} #{cmd_args.join(' ')}" }

      # For stdio servers, create a FIFO for stdin so the process stays
      # alive after the parent exits. Opening the FIFO as read+write
      # prevents EOF when no writers are connected.
      input_io = if config.transport == "stdio"
                   create_stdio_fifo(runtime_dir, key)
                 else
                   Process::Redirect::Close
                 end

      env = config.env.empty? ? nil : config.env
      process = Process.new(
        cmd,
        args: cmd_args,
        input: input_io,
        output: log_file,
        error: log_file,
        env: env,
        chdir: path
      )

      entry = ServerState.new(
        name: config.name,
        pid: process.pid.to_i64,
        transport: config.transport,
        port: nil,
        log_file: File.join(RUNTIME_DIR, "#{key}.log"),
        command: cmd,
        args: cmd_args,
        started_at: Time.utc.to_rfc3339
      )

      state.servers[key] = entry
      Log.info { "Started #{config.name} (PID #{process.pid})" }
    end

    private def stop_server(entry : ServerState)
      pid = entry.pid
      return unless process_alive?(pid)

      Log.info { "Stopping #{entry.name} (PID #{pid})..." }

      # Send SIGTERM
      send_signal(pid, Signal::TERM)

      # Wait up to 5 seconds
      50.times do
        break unless process_alive?(pid)
        sleep 0.1.seconds
      end

      # Force kill if still alive
      if process_alive?(pid)
        Log.warn { "Server #{entry.name} did not stop gracefully, sending SIGKILL" }
        send_signal(pid, Signal::KILL)
        sleep 0.2.seconds
      end

      # Clean up FIFO if present
      key = sanitize_name(entry.name)
      fifo_path = File.join(path, RUNTIME_DIR, "#{key}.stdin")
      File.delete(fifo_path) if File.exists?(fifo_path)

      Log.info { "Stopped #{entry.name}" }
    end

    private def process_alive?(pid : Int64) : Bool
      LibC.kill(pid.to_i32, 0) == 0
    end

    private def send_signal(pid : Int64, signal : Signal)
      LibC.kill(pid.to_i32, signal.value)
    rescue
      # Process may have already exited
    end

    # Creates a FIFO (named pipe) for a stdio server's stdin.
    # The FIFO is opened read+write so reads block instead of returning EOF,
    # keeping the server alive after the parent process exits.
    private def create_stdio_fifo(runtime_dir : String, key : String) : File
      fifo_path = File.join(runtime_dir, "#{key}.stdin")
      File.delete(fifo_path) if File.exists?(fifo_path)

      status = Process.run("mkfifo", [fifo_path])
      raise Error.new("Failed to create FIFO at #{fifo_path}") unless status.success?

      File.open(fifo_path, "r+")
    end

    # --- Build ---

    private def resolve_command(config : ServerConfig) : {String, Array(String)}
      if crystal_main = config.crystal_main
        binary = build_crystal_main(config.name, crystal_main)
        {binary, config.args}
      elsif cmd = config.command
        {cmd, config.args}
      else
        raise Error.new("Server #{config.name} has no command or crystal_main")
      end
    end

    private def build_crystal_main(name : String, source : String) : String
      key = sanitize_name(name)
      bin_dir = File.join(path, RUNTIME_DIR, BIN_DIR)
      Dir.mkdir_p(bin_dir) unless Dir.exists?(bin_dir)
      binary = File.join(bin_dir, key)
      source_path = File.join(path, source)

      unless File.exists?(source_path)
        raise Error.new("Crystal source not found: #{source}")
      end

      # Skip rebuild if binary is newer than source
      if File.exists?(binary) && File.info(binary).modification_time > File.info(source_path).modification_time
        Log.info { "Binary for #{name} is up to date" }
        return binary
      end

      Log.info { "Building #{name} from #{source}..." }

      args = ["build", "-o", binary, source_path]
      error = IO::Memory.new
      status = Process.run(Shards.crystal_bin, args: args, output: Process::Redirect::Inherit, error: error, chdir: path)

      unless status.success?
        raise Error.new("Failed to build #{name}:\n#{error}")
      end

      binary
    end

    # --- Name resolution ---

    private def resolve_targets(configs : Array(ServerConfig), name : String?) : Array(ServerConfig)
      return configs unless name

      [resolve_single(configs, name)]
    end

    private def resolve_single(configs : Array(ServerConfig), name : String) : ServerConfig
      # Try exact match first
      if exact = configs.find { |c| c.name == name }
        return exact
      end

      # Try partial match (just the server part after /)
      matches = configs.select { |c|
        parts = c.name.split("/")
        parts.size > 1 && parts.last == name
      }

      case matches.size
      when 0
        raise Error.new("Unknown MCP server: #{name}")
      when 1
        matches.first
      else
        names = matches.map(&.name).join(", ")
        raise Error.new("Ambiguous server name '#{name}', matches: #{names}")
      end
    end

    # --- Helpers ---

    def sanitize_name(name : String) : String
      name.gsub("/", "--")
    end

    private def print_last_lines(path : String, count : Int32)
      lines = File.read_lines(path)
      start = {lines.size - count, 0}.max
      lines[start..].each { |line| puts line }
    end
  end
end
