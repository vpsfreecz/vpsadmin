# frozen_string_literal: true

require 'json'
require 'osvm'
require 'shellwords'
require 'test-runner/hook'

class Vpsadminctl
  def initialize(machine)
    @machine = machine
  end

  def execute(args:, opts: {}, parameters: {}, timeout: nil)
    run_with_timeout(:execute, args:, opts:, parameters:, timeout:)
  end

  def succeeds(args:, opts: {}, parameters: {}, timeout: nil)
    run_with_timeout(:succeeds, args:, opts:, parameters:, timeout:)
  end

  def fails(args:, opts: {}, parameters: {}, timeout: nil)
    run_with_timeout(:fails, args:, opts:, parameters:, timeout:)
  end

  def wait_until_succeeds(args:, opts: {}, parameters: {}, timeout: nil)
    run_with_timeout(:wait_until_succeeds, args:, opts:, parameters:, timeout:)
  end

  def wait_until_fails(args:, opts: {}, parameters: {}, timeout: nil)
    run_with_timeout(:wait_until_fails, args:, opts:, parameters:, timeout:)
  end

  def all_succeed(*commands)
    commands.map { |command| succeeds(**ensure_command_hash(command)) }
  end

  def all_fail(*commands)
    commands.map { |command| fails(**ensure_command_hash(command)) }
  end

  private

  def run_with_timeout(method, args:, opts:, parameters:, timeout: nil)
    cmd = build_command(args:, opts:, parameters:)

    if timeout.nil?
      status, output = @machine.public_send(method, cmd)
    else
      status, output = @machine.public_send(method, cmd, timeout:)
    end

    [status, parse_output(output)]
  end

  def build_command(args:, opts: {}, parameters: {})
    args = ensure_args(args)
    opts = ensure_hash(opts, 'opts')
    parameters = ensure_hash(parameters, 'parameters')

    cmd = ['vpsadminctl', '--raw']
    cmd.concat(format_options(opts))
    cmd.concat(args.map(&:to_s))

    unless parameters.empty?
      cmd << '--'
      cmd.concat(format_options(parameters))
    end

    Shellwords.join(cmd)
  end

  def parse_output(output)
    json = extract_json_prefix(output)
    return output if json.nil?

    JSON.parse(json)
  rescue JSON::ParserError
    output
  end

  def extract_json_prefix(text)
    return nil unless text

    start = text.index(/\{|\[/)
    return nil if start.nil?

    stack = []
    in_string = false
    escape = false

    text.chars.each_with_index do |ch, idx|
      next if idx < start

      if in_string
        if escape
          escape = false
        elsif ch == '\\'
          escape = true
        elsif ch == '"'
          in_string = false
        end

        next
      end

      case ch
      when '"'
        in_string = true
      when '{'
        stack << '}'
      when '['
        stack << ']'
      when '}', ']'
        return nil if stack.empty?

        expected = stack.pop
        return nil if ch != expected

        return text[start..idx] if stack.empty?
      end
    end

    nil
  end

  def format_options(options)
    options.flat_map do |key, value|
      format_option(key, value)
    end
  end

  def format_option(key, value)
    kebab = option_name(key).tr('_', '-')
    positive = option_prefix(kebab)
    negative = positive.start_with?('--') ? positive.sub(/^--/, '--no-') : "--no-#{kebab}"

    case value
    when true
      [positive]
    when false
      [negative]
    when nil
      []
    when Array
      value.flat_map { |v| [positive, v.to_s] }
    else
      [positive, value.to_s]
    end
  end

  def option_prefix(kebab)
    kebab.length == 1 ? "-#{kebab}" : "--#{kebab}"
  end

  def option_name(key)
    key.to_s
  end

  def ensure_args(args)
    unless args.is_a?(Array)
      raise ArgumentError, "args must be an Array, got #{args.class}"
    end

    raise ArgumentError, 'args must not be empty' if args.empty?

    args
  end

  def ensure_hash(value, name)
    return {} if value.nil?
    raise ArgumentError, "#{name} must be a Hash, got #{value.class}" unless value.is_a?(Hash)

    value
  end

  def ensure_command_hash(value)
    raise ArgumentError, "command must be a Hash, got #{value.class}" unless value.is_a?(Hash)

    value
  end
end

class VpsadminServicesMachine < OsVm::NixosMachine
  attr_reader :vpsadminctl

  def initialize(*args, **kwargs)
    super
    @vpsadminctl = Vpsadminctl.new(self)
  end

  def wait_for_vpsadmin_api(timeout: @default_timeout || 300)
    wait_until_succeeds(
      "curl --silent --fail http://api.vpsadmin.test/ | grep 'API description'",
      timeout:
    )
  end
end

TestRunner::Hook.subscribe(:machine_class_for) do |machine_config|
  next unless machine_config.tags.include?('vpsadmin-services')

  VpsadminServicesMachine
end
