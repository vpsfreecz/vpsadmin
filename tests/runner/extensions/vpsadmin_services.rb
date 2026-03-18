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
  CHAIN_STATES = {
    staged: 0,
    queued: 1,
    done: 2,
    rollbacking: 3,
    failed: 4,
    fatal: 5,
    resolved: 6
  }.freeze

  attr_reader :vpsadminctl

  def initialize(*args, **kwargs)
    super
    @vpsadminctl = Vpsadminctl.new(self)
  end

  def wait_for_vpsadmin_api(timeout: @default_timeout || 300)
    deadline = Time.now + timeout

    loop do
      remaining = deadline - Time.now
      raise OsVm::TimeoutError, 'Timeout occurred while waiting for vpsadmin API' if remaining <= 0

      _, output = wait_until_succeeds(
        'curl --silent --fail-with-body http://api.vpsadmin.test/',
        timeout: remaining.ceil
      )

      return true if output.include?('API description')

      sleep 1
    end
  end

  def mysql_raw(sql:, database: 'vpsadmin', user: 'api', timeout: nil)
    cmd = mysql_command(sql:, database:, user:)

    if timeout.nil?
      succeeds(cmd)
    else
      succeeds(cmd, timeout:)
    end
  end

  def mysql_scalar(sql:, database: 'vpsadmin', user: 'api', timeout: nil)
    _, output = mysql_raw(sql:, database:, user:, timeout:)
    output.to_s.lines.first&.strip
  end

  def mysql_rows(sql:, database: 'vpsadmin', user: 'api', timeout: nil)
    _, output = mysql_raw(sql:, database:, user:, timeout:)
    output.to_s.lines.map { |line| line.chomp.split("\t", -1) }
  end

  def mysql_json_rows(sql:, database: 'vpsadmin', user: 'api', timeout: nil)
    mysql_rows(sql:, database:, user:, timeout:).map do |row|
      JSON.parse(row.fetch(0))
    end
  end

  def wait_for_chain_state(chain_id, state:, timeout: @default_timeout || 300)
    expected = state.is_a?(Symbol) ? CHAIN_STATES.fetch(state) : Integer(state)

    wait_for_condition(
      timeout:,
      error_message: "Timed out waiting for chain ##{chain_id} state=#{state}"
    ) do
      current = mysql_scalar(
        sql: "SELECT state FROM transaction_chains WHERE id = #{Integer(chain_id)}"
      )

      current && current.to_i == expected
    end
  end

  def wait_for_chain_progress(chain_id, progress:, timeout: @default_timeout || 300)
    expected = Integer(progress)

    wait_for_condition(
      timeout:,
      error_message: "Timed out waiting for chain ##{chain_id} progress=#{expected}"
    ) do
      current = mysql_scalar(
        sql: "SELECT progress FROM transaction_chains WHERE id = #{Integer(chain_id)}"
      )

      current && current.to_i == expected
    end
  end

  def wait_for_transaction(transaction_id, done:, status: nil, timeout: @default_timeout || 300)
    expected_done = Integer(done)
    expected_status = status.nil? ? nil : Integer(status)

    wait_for_condition(
      timeout:,
      error_message: "Timed out waiting for transaction ##{transaction_id} done=#{expected_done} status=#{expected_status.inspect}"
    ) do
      row = mysql_rows(
        sql: <<~SQL
          SELECT done, status
          FROM transactions
          WHERE id = #{Integer(transaction_id)}
        SQL
      ).first

      next false unless row

      current_done, current_status = row.map(&:to_i)
      current_done == expected_done && (expected_status.nil? || current_status == expected_status)
    end
  end

  def wait_for_no_confirmations(chain_id, timeout: @default_timeout || 300)
    wait_for_condition(
      timeout:,
      error_message: "Timed out waiting for chain ##{chain_id} confirmations to finish"
    ) do
      current = mysql_scalar(
        sql: <<~SQL
          SELECT COUNT(*)
          FROM transaction_confirmations c
          INNER JOIN transactions t ON t.id = c.transaction_id
          WHERE t.transaction_chain_id = #{Integer(chain_id)} AND c.done = 0
        SQL
      )

      current && current.to_i == 0
    end
  end

  def unlock_transaction_signing_key(passphrase: 'test')
    _, output = vpsadminctl.succeeds(
      args: %w[api_server unlock_transaction_signing_key],
      parameters: { passphrase: }
    )

    output
  end

  private

  def mysql_command(sql:, database:, user:)
    password_file = "/etc/vpsadmin-test/mariadb-#{user}-password"

    inner = [
      'mariadb',
      '--batch',
      '--raw',
      '--skip-column-names',
      "--user=#{Shellwords.escape(user)}",
      "--password=\"$(cat #{Shellwords.escape(password_file)})\"",
      Shellwords.escape(database),
      '-e',
      Shellwords.escape(sql)
    ].join(' ')

    "bash -lc #{Shellwords.escape(inner)}"
  end

  def wait_for_condition(timeout:, error_message:)
    deadline = Time.now + timeout

    loop do
      return true if yield

      raise OsVm::TimeoutError, error_message if Time.now >= deadline

      sleep 1
    end
  end
end

TestRunner::Hook.subscribe(:machine_class_for) do |machine_config|
  next unless machine_config.tags.include?('vpsadmin-services')

  VpsadminServicesMachine
end
