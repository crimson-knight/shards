require "./spec_helper"
require "json"

private def write_mcp_shards_json(servers : Hash(String, Hash(String, String | Array(String))))
  mcp_config = {
    "mcpServers" => servers.transform_values { |v| JSON::Any.new(v.transform_values { |val|
      case val
      when String        then JSON::Any.new(val)
      when Array(String) then JSON::Any.new(val.map { |s| JSON::Any.new(s) })
      else                    JSON::Any.new(val.to_s)
      end
    }) },
  }
  File.write(".mcp-shards.json", mcp_config.to_pretty_json + "\n")
end

private def read_servers_json : JSON::Any
  path = File.join(".shards", "mcp", "servers.json")
  JSON.parse(File.read(path))
end

private def cleanup_mcp_processes
  state_path = File.join(".shards", "mcp", "servers.json")
  if File.exists?(state_path)
    begin
      state = JSON.parse(File.read(state_path))
      if servers = state["servers"]?.try(&.as_h?)
        servers.each do |_, entry|
          if pid = entry["pid"]?.try(&.as_i64?)
            Process.run("kill", ["-9", pid.to_s]) rescue nil
          end
        end
      end
    rescue
    end
  end
end

describe "mcp" do
  after_each do
    Dir.cd(application_path) do
      cleanup_mcp_processes
    end
  end

  describe "status" do
    it "shows no servers when .mcp-shards.json is missing" do
      with_shard({name: "test"}) do
        output = run "shards mcp"
        output.should contain("No MCP servers configured")
      end
    end

    it "shows servers as stopped when configured but not started" do
      with_shard({name: "test"}) do
        write_mcp_shards_json({
          "my_shard/explorer" => {
            "command" => "sleep",
            "args"    => ["60"],
          } of String => String | Array(String),
        })

        output = run "shards mcp"
        output.should contain("my_shard/explorer")
        output.should contain("[stopped]")
      end
    end
  end

  describe "start" do
    it "starts a server and shows running status" do
      with_shard({name: "test"}) do
        write_mcp_shards_json({
          "my_shard/sleeper" => {
            "command" => "sleep",
            "args"    => ["300"],
          } of String => String | Array(String),
        })

        run "shards mcp start"
        output = run "shards mcp"
        output.should contain("my_shard/sleeper")
        output.should contain("[running]")
        output.should contain("PID")
      end
    end

    it "starts a specific server by name" do
      with_shard({name: "test"}) do
        write_mcp_shards_json({
          "shard_a/server1" => {
            "command" => "sleep",
            "args"    => ["300"],
          } of String => String | Array(String),
          "shard_b/server2" => {
            "command" => "sleep",
            "args"    => ["300"],
          } of String => String | Array(String),
        })

        run "shards mcp start shard_a/server1"
        output = run "shards mcp"
        output.should contain("shard_a/server1")
        output.should contain("[running]")
        # server2 should still be stopped
        output.should match(/shard_b\/server2.*\[stopped\]/)
      end
    end

    it "starts a server by partial name" do
      with_shard({name: "test"}) do
        write_mcp_shards_json({
          "my_shard/explorer" => {
            "command" => "sleep",
            "args"    => ["300"],
          } of String => String | Array(String),
        })

        run "shards mcp start explorer"
        output = run "shards mcp"
        output.should contain("my_shard/explorer")
        output.should contain("[running]")
      end
    end

    it "creates log file in .shards/mcp/" do
      with_shard({name: "test"}) do
        write_mcp_shards_json({
          "my_shard/logger" => {
            "command" => "sleep",
            "args"    => ["300"],
          } of String => String | Array(String),
        })

        run "shards mcp start"
        File.exists?(File.join(".shards", "mcp", "my_shard--logger.log")).should be_true
      end
    end

    it "creates servers.json state file" do
      with_shard({name: "test"}) do
        write_mcp_shards_json({
          "my_shard/tracker" => {
            "command" => "sleep",
            "args"    => ["300"],
          } of String => String | Array(String),
        })

        run "shards mcp start"
        state = read_servers_json
        state["version"].should eq("1.0")
        state["servers"]["my_shard--tracker"]["name"].should eq("my_shard/tracker")
        state["servers"]["my_shard--tracker"]["pid"].as_i64.should be > 0
      end
    end
  end

  describe "stop" do
    it "stops a running server" do
      with_shard({name: "test"}) do
        write_mcp_shards_json({
          "my_shard/stopper" => {
            "command" => "sleep",
            "args"    => ["300"],
          } of String => String | Array(String),
        })

        run "shards mcp start"
        output = run "shards mcp"
        output.should contain("[running]")

        run "shards mcp stop"
        output = run "shards mcp"
        output.should contain("[stopped]")
      end
    end

    it "handles already-stopped server gracefully" do
      with_shard({name: "test"}) do
        write_mcp_shards_json({
          "my_shard/already" => {
            "command" => "sleep",
            "args"    => ["300"],
          } of String => String | Array(String),
        })

        # Stop without starting should not error
        output = run "shards mcp stop"
        output.should contain("not running")
      end
    end
  end

  describe "restart" do
    it "restarts a server with a new PID" do
      with_shard({name: "test"}) do
        write_mcp_shards_json({
          "my_shard/restarter" => {
            "command" => "sleep",
            "args"    => ["300"],
          } of String => String | Array(String),
        })

        run "shards mcp start"
        state1 = read_servers_json
        pid1 = state1["servers"]["my_shard--restarter"]["pid"].as_i64

        # Small delay to ensure new process gets different PID
        sleep 200.milliseconds

        run "shards mcp restart"
        state2 = read_servers_json
        pid2 = state2["servers"]["my_shard--restarter"]["pid"].as_i64

        pid2.should_not eq(pid1)
      end
    end
  end

  describe "logs" do
    it "shows log content with --no-follow" do
      with_shard({name: "test"}) do
        write_mcp_shards_json({
          "my_shard/echoer" => {
            "command" => "/bin/sh",
            "args"    => ["-c", "echo 'hello from mcp server' && sleep 300"],
          } of String => String | Array(String),
        })

        run "shards mcp start"
        # Give the process time to write output
        sleep 500.milliseconds

        output = run "shards mcp logs echoer --no-follow"
        output.should contain("hello from mcp server")
      end
    end

    it "errors when server name is missing" do
      with_shard({name: "test"}) do
        write_mcp_shards_json({
          "my_shard/any" => {
            "command" => "sleep",
            "args"    => ["300"],
          } of String => String | Array(String),
        })

        ex = expect_raises(FailedCommand) { run "shards mcp logs --no-color" }
        ex.stdout.should contain("Usage")
      end
    end
  end

  describe "stale PID detection" do
    it "detects externally killed process as stopped" do
      with_shard({name: "test"}) do
        write_mcp_shards_json({
          "my_shard/stale" => {
            "command" => "sleep",
            "args"    => ["300"],
          } of String => String | Array(String),
        })

        run "shards mcp start"
        state = read_servers_json
        pid = state["servers"]["my_shard--stale"]["pid"].as_i64

        # Kill the process externally
        Process.run("kill", ["-9", pid.to_s])
        sleep 200.milliseconds

        output = run "shards mcp"
        output.should contain("[stopped]")
      end
    end
  end

  describe "error handling" do
    it "errors on unknown server name" do
      with_shard({name: "test"}) do
        write_mcp_shards_json({
          "my_shard/real" => {
            "command" => "sleep",
            "args"    => ["300"],
          } of String => String | Array(String),
        })

        ex = expect_raises(FailedCommand) { run "shards mcp start nonexistent --no-color" }
        ex.stdout.should contain("Unknown MCP server")
      end
    end

    it "errors on unknown subcommand" do
      with_shard({name: "test"}) do
        ex = expect_raises(FailedCommand) { run "shards mcp invalid --no-color" }
        ex.stdout.should contain("Unknown mcp subcommand")
      end
    end
  end
end
