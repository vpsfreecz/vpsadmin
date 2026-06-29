# frozen_string_literal: true

require 'json'
require 'osvm'
require 'shellwords'
require 'test-runner/hook'
require 'uri'

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
  MAILPIT_API_URL = 'http://127.0.0.1:8025/api/v1'

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

  def wait_for_mailpit(timeout: @default_timeout || 300)
    wait_until_succeeds(mailpit_curl_command('/info'), timeout:)
    true
  end

  def mailpit_info(timeout: nil)
    mailpit_json('/info', timeout:)
  end

  def clear_mailpit(timeout: nil)
    mailpit_request('/messages', method: 'DELETE', timeout:)
    true
  end

  def mailpit_messages(start: 0, limit: 50, timeout: nil)
    query = URI.encode_www_form(start:, limit:)
    mailpit_json("/messages?#{query}", timeout:)
  end

  def mailpit_message(id, timeout: nil)
    mailpit_json("/message/#{URI.encode_www_form_component(id)}", timeout:)
  end

  def wait_for_mailpit_message(
    to: nil,
    subject: nil,
    subject_prefix: nil,
    text_includes: [],
    html_includes: [],
    timeout: @default_timeout || 300
  )
    found = nil
    criteria = mailpit_criteria(to:, subject:, subject_prefix:)

    wait_for_condition(
      timeout:,
      error_message: "Timed out waiting for Mailpit message #{criteria.inspect}"
    ) do
      found = find_mailpit_message(
        to:,
        subject:,
        subject_prefix:,
        text_includes:,
        html_includes:
      )
    end

    found
  end

  def find_mailpit_message(
    to: nil,
    subject: nil,
    subject_prefix: nil,
    text_includes: [],
    html_includes: []
  )
    mailpit_messages(limit: 100).fetch('messages').each do |summary|
      next unless mailpit_summary_matches?(summary, to:, subject:, subject_prefix:)

      message = mailpit_message(summary.fetch('ID'))
      next unless mailpit_message_body_matches?(message, text_includes:, html_includes:)

      return message
    end

    nil
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

  def run_vps_migration_task(timeout: nil)
    api_ruby_json(code: <<~RUBY, timeout: timeout)
      VpsAdmin::API::Tasks::VpsMigration.new.run_plans
      puts JSON.dump(ok: true)
    RUBY
  end

  def migration_plan_row(plan_id)
    api_ruby_json(code: <<~RUBY)
      plan = MigrationPlan.find(#{Integer(plan_id)})
      puts JSON.dump(
        id: plan.id,
        state: plan.state,
        concurrency: plan.concurrency,
        stop_on_error: plan.stop_on_error,
        finished_at: plan.finished_at,
        lock_count: plan.resource_locks.count
      )
    RUBY
  end

  def vps_migration_rows(plan_id)
    api_ruby_json(code: <<~RUBY)
      rows = VpsMigration.where(
        migration_plan_id: #{Integer(plan_id)}
      ).order(:id).map do |migration|
        {
          id: migration.id,
          vps_id: migration.vps_id,
          src_node_id: migration.src_node_id,
          dst_node_id: migration.dst_node_id,
          state: migration.state,
          started_at: migration.started_at,
          finished_at: migration.finished_at,
          chain_id: migration.transaction_chain_id
        }
      end

      puts JSON.dump(rows)
    RUBY
  end

  def migration_plan_debug_snapshot(plan_id)
    api_ruby_json(code: <<~RUBY, timeout: 120)
      def fmt_time(value)
        value && value.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
      end

      def output_tail(value)
        return nil if value.nil?

        str = value.to_s
        str.length > 500 ? str[-500, 500] : str
      end

      plan = MigrationPlan.find(#{Integer(plan_id)})
      migrations = plan.vps_migrations.includes(transaction_chain: :transactions).order(:id).map do |migration|
        chain = migration.transaction_chain
        transactions =
          if chain
            unfinished = chain.transactions.where(done: Transaction.dones[:waiting]).order(:id).limit(12).to_a
            selected = unfinished.any? ? unfinished : chain.transactions.order(id: :desc).limit(12).to_a.reverse

            selected.map do |tx|
              {
                id: tx.id,
                name: tx.name,
                handle: tx.handle,
                node_id: tx.node_id,
                queue: tx.queue,
                done: tx.done,
                status: tx.status,
                urgent: tx.urgent,
                started_at: fmt_time(tx.started_at),
                finished_at: fmt_time(tx.finished_at),
                output_tail: output_tail(tx.output)
              }
            end
          else
            []
          end

        {
          id: migration.id,
          vps_id: migration.vps_id,
          state: migration.state,
          src_node_id: migration.src_node_id,
          dst_node_id: migration.dst_node_id,
          started_at: fmt_time(migration.started_at),
          finished_at: fmt_time(migration.finished_at),
          chain: chain && {
            id: chain.id,
            state: chain.state,
            progress: chain.progress,
            size: chain.size
          },
          transactions: transactions
        }
      end

      puts JSON.dump(
        plan: {
          id: plan.id,
          state: plan.state,
          concurrency: plan.concurrency,
          stop_on_error: plan.stop_on_error,
          lock_count: plan.resource_locks.count,
          finished_at: fmt_time(plan.finished_at)
        },
        migrations: migrations
      )
    RUBY
  end

  def wait_for_migration_plan_state(plan_id, state:, timeout: @default_timeout || 300)
    expected = state.to_s
    row = nil

    wait_for_condition(
      timeout: timeout,
      error_message: "Timed out waiting for migration plan ##{plan_id} state=#{expected}"
    ) do
      row = migration_plan_row(plan_id)
      row.fetch('state') == expected
    end

    row
  end

  def wait_for_vps_migration_state(plan_id, vps_id:, state:, timeout: @default_timeout || 300)
    expected = state.to_s
    row = nil

    wait_for_condition(
      timeout: timeout,
      error_message: "Timed out waiting for VPS #{vps_id} migration in plan ##{plan_id} state=#{expected}"
    ) do
      row = vps_migration_rows(plan_id).detect { |migration| migration.fetch('vps_id') == Integer(vps_id) }
      row && row.fetch('state') == expected
    end

    row
  end

  def mariadb_raw(sql:, database: 'vpsadmin', user: 'api', timeout: nil)
    cmd = mariadb_command(sql:, database:, user:)

    if timeout.nil?
      succeeds(cmd)
    else
      succeeds(cmd, timeout:)
    end
  end

  def mariadb_scalar(sql:, database: 'vpsadmin', user: 'api', timeout: nil)
    _, output = mariadb_raw(sql:, database:, user:, timeout:)
    output.to_s.lines.first&.strip
  end

  def mariadb_rows(sql:, database: 'vpsadmin', user: 'api', timeout: nil)
    _, output = mariadb_raw(sql:, database:, user:, timeout:)
    output.to_s.lines.map { |line| line.chomp.split("\t", -1) }
  end

  def mariadb_json_rows(sql:, database: 'vpsadmin', user: 'api', timeout: nil)
    mariadb_rows(sql:, database:, user:, timeout:).map do |row|
      JSON.parse(row.fetch(0))
    end
  end

  def wait_for_chain_state(chain_id, state:, timeout: @default_timeout || 300)
    expected = state.is_a?(Symbol) ? CHAIN_STATES.fetch(state) : Integer(state)

    wait_for_condition(
      timeout:,
      error_message: "Timed out waiting for chain ##{chain_id} state=#{state}"
    ) do
      current = mariadb_scalar(
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
      current = mariadb_scalar(
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
      current = mariadb_scalar(
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
      row = mariadb_rows(
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
      current = mariadb_scalar(
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
      current = mariadb_scalar(
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
      current = mariadb_scalar(
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
      current = mariadb_scalar(
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
      current = mariadb_scalar(
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

  def mailpit_criteria(to:, subject:, subject_prefix:)
    {
      to:,
      subject:,
      subject_prefix:
    }.compact
  end

  def mailpit_summary_matches?(summary, to:, subject:, subject_prefix:)
    expected_to = Array(to).compact
    addresses = mailpit_addresses(summary, 'To')

    return false if expected_to.any? && (expected_to - addresses).any?
    return false if subject && summary['Subject'] != subject
    return false if subject_prefix && !summary['Subject'].to_s.start_with?(subject_prefix)

    true
  end

  def mailpit_message_body_matches?(message, text_includes:, html_includes:)
    Array(text_includes).all? { |needle| message['Text'].to_s.include?(needle) } &&
      Array(html_includes).all? { |needle| message['HTML'].to_s.include?(needle) }
  end

  def mailpit_addresses(message, field)
    Array(message[field]).map { |addr| addr.fetch('Address').to_s }
  end

  def mailpit_json(path, method: 'GET', body: nil, timeout: nil)
    _, output = mailpit_request(path, method:, body:, timeout:)
    JSON.parse(output)
  end

  def mailpit_request(path, method: 'GET', body: nil, timeout: nil)
    cmd = mailpit_curl_command(path, method:, body:)
    timeout ? succeeds(cmd, timeout:) : succeeds(cmd)
  end

  def mailpit_curl_command(path, method: 'GET', body: nil)
    args = [
      'curl',
      '--silent',
      '--show-error',
      '--fail-with-body',
      '--connect-timeout',
      '2',
      '--max-time',
      '10',
      '--request',
      method,
      mailpit_api_url(path)
    ]

    args.push('--header', 'Content-Type: application/json', '--data', JSON.dump(body)) if body

    Shellwords.join(args)
  end

  def mailpit_api_url(path)
    "#{MAILPIT_API_URL}#{path.start_with?('/') ? path : "/#{path}"}"
  end

  def mariadb_command(sql:, database:, user:)
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
