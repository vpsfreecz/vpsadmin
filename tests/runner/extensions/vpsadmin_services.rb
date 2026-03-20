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

  def api_ruby(code:, timeout: nil)
    script = <<~CMD
      set -euo pipefail
      api_dir="$(systemctl show -p WorkingDirectory --value vpsadmin-api)"
      api_root="$(dirname "$api_dir")"
      tmp_rb="$(mktemp /tmp/vpsadmin-storage-XXXX.rb)"
      trap 'rm -f "$tmp_rb"' EXIT

      cat > "$tmp_rb" <<'RUBY'
      ENV['RACK_ENV'] ||= 'production'
      require 'json'
      Dir.chdir(ENV.fetch('API_DIR'))
      $LOAD_PATH.unshift(File.join(ENV.fetch('API_DIR'), 'lib'))
      require 'vpsadmin'
      #{code}
      RUBY

      API_DIR="$api_dir" "$api_root/ruby-env-wrapped/bin/ruby" "$tmp_rb"
    CMD

    timeout ? succeeds(script, timeout: timeout) : succeeds(script)
  end

  def api_ruby_json(code:, timeout: nil)
    _, output = api_ruby(code: code, timeout: timeout)
    JSON.parse(output.to_s.lines.last)
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

  def wait_for_chain_states(chain_id, states:, timeout: @default_timeout || 300)
    expected = Array(states).map do |state|
      state.is_a?(Symbol) ? CHAIN_STATES.fetch(state) : Integer(state)
    end

    wait_for_condition(
      timeout:,
      error_message: "Timed out waiting for chain ##{chain_id} state in #{states.inspect}"
    ) do
      current = mysql_scalar(
        sql: "SELECT state FROM transaction_chains WHERE id = #{Integer(chain_id)}"
      )

      current && expected.include?(current.to_i)
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

  def wait_for_snapshot_in_pool(dip_id, snapshot_id, timeout: @default_timeout || 300)
    wait_for_condition(
      timeout: timeout,
      error_message: "Timed out waiting for snapshot #{snapshot_id} in DatasetInPool ##{dip_id}"
    ) do
      current = mysql_scalar(
        sql: <<~SQL
          SELECT COUNT(*)
          FROM snapshot_in_pools
          WHERE dataset_in_pool_id = #{Integer(dip_id)} AND snapshot_id = #{Integer(snapshot_id)}
        SQL
      )

      current && current.to_i > 0
    end
  end

  def wait_for_dataset_in_pool(dataset_id:, pool_id:, timeout: @default_timeout || 300)
    wait_for_condition(
      timeout: timeout,
      error_message: "Timed out waiting for DatasetInPool dataset=#{dataset_id} pool=#{pool_id}"
    ) do
      current = mysql_scalar(
        sql: <<~SQL
          SELECT id
          FROM dataset_in_pools
          WHERE dataset_id = #{Integer(dataset_id)} AND pool_id = #{Integer(pool_id)}
          LIMIT 1
        SQL
      )

      !current.nil? && !current.empty?
    end
  end

  def wait_for_branch_count(dip_id, count:, timeout: @default_timeout || 300)
    wait_for_condition(
      timeout: timeout,
      error_message: "Timed out waiting for DatasetInPool ##{dip_id} branch count=#{count}"
    ) do
      current = mysql_scalar(
        sql: <<~SQL
          SELECT COUNT(*)
          FROM branches b
          INNER JOIN dataset_trees t ON t.id = b.dataset_tree_id
          WHERE t.dataset_in_pool_id = #{Integer(dip_id)}
        SQL
      )

      current && current.to_i == Integer(count)
    end
  end

  def wait_for_tree_count(dip_id, count:, timeout: @default_timeout || 300)
    wait_for_condition(
      timeout: timeout,
      error_message: "Timed out waiting for DatasetInPool ##{dip_id} tree count=#{count}"
    ) do
      current = mysql_scalar(
        sql: <<~SQL
          SELECT COUNT(*)
          FROM dataset_trees
          WHERE dataset_in_pool_id = #{Integer(dip_id)}
        SQL
      )

      current && current.to_i == Integer(count)
    end
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

module ZfsMachineHelpers
  def zfs_get(fs:, property:, timeout: nil)
    cmd = [
      'zfs get -H -o value',
      Shellwords.escape(property.to_s),
      Shellwords.escape(fs)
    ].join(' ')

    status, output = timeout ? succeeds(cmd, timeout: timeout) : succeeds(cmd)
    [status, output.to_s.strip]
  end

  def zfs_list(fs:, types: 'filesystem,snapshot', recursive: true, timeout: nil)
    cmd = [
      'zfs list -H -o name',
      ("-t #{types}" if types),
      ('-r' if recursive),
      Shellwords.escape(fs)
    ].compact.join(' ')

    status, output = timeout ? succeeds(cmd, timeout: timeout) : succeeds(cmd)
    [status, output.to_s.lines.map(&:strip).reject(&:empty?)]
  end

  def zfs_list_rows(fs:, columns:, types: 'filesystem,snapshot', recursive: true, timeout: nil)
    cols = Array(columns)

    cmd = [
      'zfs list -H',
      "-o #{cols.join(',')}",
      ("-t #{types}" if types),
      ('-r' if recursive),
      Shellwords.escape(fs)
    ].compact.join(' ')

    status, output = timeout ? succeeds(cmd, timeout: timeout) : succeeds(cmd)

    rows = output.to_s.lines.map do |line|
      cols.zip(line.chomp.split("\t", -1)).to_h
    end

    [status, rows]
  end

  def zfs_exists?(name, type: nil, timeout: nil)
    _, rows = zfs_list(fs: name, types: type, recursive: false, timeout: timeout)
    rows.include?(name)
  rescue StandardError
    false
  end

  def zfs_snapshots(fs:, timeout: nil)
    _, rows = zfs_list(fs: fs, types: 'snapshot', recursive: true, timeout: timeout)
    rows
  end
end

OsVm::NixosMachine.include(ZfsMachineHelpers)
OsVm::VpsadminosMachine.include(ZfsMachineHelpers)

TestRunner::Hook.subscribe(:machine_class_for) do |machine_config|
  next unless machine_config.tags.include?('vpsadmin-services')

  VpsadminServicesMachine
end
