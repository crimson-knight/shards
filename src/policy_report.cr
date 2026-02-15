require "colorize"
require "json"

module Shards
  class PolicyReport
    enum Severity
      Error
      Warning
    end

    record Violation,
      package : String,
      rule : String,
      severity : Severity,
      message : String

    getter violations : Array(Violation)

    def initialize
      @violations = [] of Violation
    end

    def add_violation(package : String, rule : String, severity : Severity, message : String)
      @violations << Violation.new(package: package, rule: rule, severity: severity, message: message)
    end

    def errors
      @violations.select(&.severity.error?)
    end

    def warnings
      @violations.select(&.severity.warning?)
    end

    def clean?
      @violations.empty?
    end

    def has_errors?
      @violations.any?(&.severity.error?)
    end

    def has_warnings?
      @violations.any?(&.severity.warning?)
    end

    def exit_code(strict : Bool = false) : Int32
      if has_errors?
        1
      elsif has_warnings? && strict
        1
      elsif has_warnings?
        2
      else
        0
      end
    end

    def to_terminal(io : IO, colors : Bool = Shards.colors?)
      if clean?
        msg = "Policy check passed: no violations found"
        io.puts colors ? msg.colorize(:green) : msg
        return
      end

      errors.each do |v|
        prefix = colors ? "ERROR".colorize(:red).bold : "ERROR"
        io.puts "  #{prefix} [#{v.rule}] #{v.message}"
      end

      warnings.each do |v|
        prefix = colors ? "WARN".colorize(:yellow) : "WARN"
        io.puts "  #{prefix}  [#{v.rule}] #{v.message}"
      end

      summary_parts = [] of String
      summary_parts << "#{errors.size} error(s)" if errors.any?
      summary_parts << "#{warnings.size} warning(s)" if warnings.any?
      io.puts
      io.puts "Policy check: #{summary_parts.join(", ")}"
    end

    def to_json_output(io : IO)
      JSON.build(io, indent: 2) do |json|
        json.object do
          json.field "violations" do
            json.array do
              @violations.each do |v|
                json.object do
                  json.field "package", v.package
                  json.field "rule", v.rule
                  json.field "severity", v.severity.to_s.downcase
                  json.field "message", v.message
                end
              end
            end
          end
          json.field "summary" do
            json.object do
              json.field "errors", errors.size
              json.field "warnings", warnings.size
              json.field "total", @violations.size
            end
          end
        end
      end
    end
  end
end
