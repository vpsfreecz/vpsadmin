{
  adminUserId ? 0,
  node1Id ? 0,
  node2Id ? 0,
  primaryPoolFs ? "tank/ct",
  backupPoolFs ? "tank/backup",
  manageCluster ? true,
}:
''
  require 'json'
  require 'fileutils'
  require 'shellwords'
  require 'time'
  require ${builtins.toJSON ../../../../api/lib/storage_topology_fixture.rb}

  admin_user_id = ${toString adminUserId}
  node1_id = ${toString node1Id}
  node2_id = ${toString node2Id}
  primary_pool_fs = '${primaryPoolFs}'
  backup_pool_fs = '${backupPoolFs}'

  def admin_user_id
    ${toString adminUserId}
  end

  def node1_id
    ${toString node1Id}
  end

  def node2_id
    ${toString node2Id}
  end

  def primary_pool_fs
    ${builtins.toJSON primaryPoolFs}
  end

  def backup_pool_fs
    ${builtins.toJSON backupPoolFs}
  end

  def wait_for_running_nodectld(node)
    node.wait_for_service('nodectld')
    wait_until_block_succeeds(name: "nodectld supervised on #{node.name}") do
      _, output = node.succeeds('sv check nodectld', timeout: 30)
      expect(output).to include('ok: run: nodectld')
      true
    end
  end

  def wait_for_node_ready(services, node_id)
    wait_until_block_succeeds(name: "node #{node_id} ready in API") do
      _, output = services.vpsadminctl.succeeds(args: ['node', 'show', node_id.to_s])
      node = output.fetch('node')

      node.fetch('status') == true && node.fetch('pool_status') == true
    end
  end

  def prepare_node_queues(node, send_timeout: 120, receive_timeout: 120)
    node.succeeds('nodectl set config vpsadmin.queues.zfs_send.start_delay=0', timeout: 60)
    node.succeeds('nodectl set config vpsadmin.queues.zfs_recv.start_delay=0', timeout: 60)
    node.succeeds('nodectl queue resume all', timeout: 60)
  end

  def wait_for_pool_online(services, pool_id)
    wait_until_block_succeeds(name: "pool #{pool_id} online") do
      _, output = services.vpsadminctl.succeeds(args: ['pool', 'show', pool_id.to_s])
      output.fetch('pool').fetch('state') == 'online'
    end
  end

  def api_session_prelude(admin_user_id)
    <<~RUBY
      user = User.find(#{admin_user_id})
      User.current = user
      UserSession.current = UserSession.create!(
        user: user,
        auth_type: 'basic',
        api_ip_addr: '127.0.0.1',
        client_version: 'storage-integration'
      )
    RUBY
  end

  def storage_tx_types(services)
    services.api_ruby_json(code: <<~RUBY)
      puts JSON.dump(
        create_tree: Transactions::Storage::CreateTree.t_type,
        recv: Transactions::Storage::Recv.t_type,
        send: Transactions::Storage::Send.t_type,
        recv_check: Transactions::Storage::RecvCheck.t_type,
        download_snapshot: Transactions::Storage::DownloadSnapshot.t_type,
        remove_download: Transactions::Storage::RemoveDownload.t_type,
        rsync_dataset: Transactions::Storage::RsyncDataset.t_type,
        local_send: Transactions::Storage::LocalSend.t_type,
        prepare_rollback: Transactions::Storage::PrepareRollback.t_type,
        apply_rollback: Transactions::Storage::ApplyRollback.t_type,
        branch_dataset: Transactions::Storage::BranchDataset.t_type,
        destroy_snapshot: Transactions::Storage::DestroySnapshot.t_type,
        rollback: Transactions::Storage::Rollback.t_type,
        queue_reserve: Transactions::Queue::Reserve.t_type,
        queue_release: Transactions::Queue::Release.t_type,
        export_create: Transactions::Export::Create.t_type,
        export_destroy: Transactions::Export::Destroy.t_type,
        export_disable: Transactions::Export::Disable.t_type,
        export_add_hosts: Transactions::Export::AddHosts.t_type,
        export_enable: Transactions::Export::Enable.t_type,
        authorize_send_key: Transactions::Pool::AuthorizeSendKey.t_type,
        vps_send_config: Transactions::Vps::SendConfig.t_type,
        vps_send_rootfs: Transactions::Vps::SendRootfs.t_type,
        vps_send_state: Transactions::Vps::SendState.t_type,
        vps_send_cleanup: Transactions::Vps::SendCleanup.t_type,
        vps_remove_config: Transactions::Vps::RemoveConfig.t_type,
        vps_stop: Transactions::Vps::Stop.t_type,
        vps_start: Transactions::Vps::Start.t_type
      )
    RUBY
  end

  def tx_types(services)
    @tx_types ||= storage_tx_types(services)
  end

  def ensure_snapshot_download_base_url(services, base_url: 'https://downloads.example.test')
    services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      cfg = SysConfig.find_or_initialize_by(
        category: 'core',
        name: 'snapshot_download_base_url'
      )
      cfg.data_type ||= 'String'
      cfg.value = #{base_url.inspect}
      cfg.save! if cfg.changed?

      puts JSON.dump(base_url: cfg.value)
    RUBY
  end

  def generate_migration_keys(services)
    services.vpsadminctl.succeeds(args: %w[cluster generate_migration_keys])
  end

  def create_pool(services, node_id:, label:, filesystem:, role:)
    _, output = services.vpsadminctl.succeeds(
      args: %w[pool create],
      parameters: {
        node: node_id,
        label: label,
        filesystem: filesystem,
        role: role,
        is_open: true,
        max_datasets: 100,
        refquota_check: true
      }
    )

    output.fetch('pool')
  end

  def create_vps(services, admin_user_id:, node_id:, hostname:)
    _, output = services.vpsadminctl.succeeds(
      args: %w[vps new],
      parameters: {
        user: admin_user_id,
        node: node_id,
        os_template: 1,
        hostname: hostname,
        cpu: 1,
        memory: 1024,
        swap: 0,
        diskspace: 10240,
        ipv4: 0,
        ipv4_private: 0,
        ipv6: 0
      }
    )

    output.fetch('vps')
  end

  def dataset_info(services, vps_id)
    services.mysql_json_rows(sql: <<~SQL).first
      SELECT JSON_OBJECT(
        'dataset_id', d.id,
        'dataset_in_pool_id', dip.id,
        'dataset_full_name', d.full_name,
        'pool_id', p.id,
        'pool_filesystem', p.filesystem
      )
      FROM vpses v
      INNER JOIN dataset_in_pools dip ON dip.id = v.dataset_in_pool_id
      INNER JOIN datasets d ON d.id = dip.dataset_id
      INNER JOIN pools p ON p.id = dip.pool_id
      WHERE v.id = #{Integer(vps_id)}
    SQL
  end

  def snapshot_rows_for_dip(services, dip_id)
    services.mysql_json_rows(sql: <<~SQL)
      SELECT JSON_OBJECT(
        'id', s.id,
        'snapshot_in_pool_id', sip.id,
        'name', s.name,
        'history_id', s.history_id
      )
      FROM snapshot_in_pools sip
      INNER JOIN snapshots s ON s.id = sip.snapshot_id
      WHERE sip.dataset_in_pool_id = #{Integer(dip_id)}
      ORDER BY s.id
    SQL
  end

  def head_tree_row(services, dip_id)
    services.mysql_json_rows(sql: <<~SQL).first
      SELECT JSON_OBJECT(
        'tree_id', t.id,
        'tree_index', t.`index`,
        'head', t.head
      )
      FROM dataset_trees t
      WHERE t.dataset_in_pool_id = #{Integer(dip_id)} AND t.head = 1
      LIMIT 1
    SQL
  end

  def head_branch_row(services, dip_id)
    services.mysql_json_rows(sql: <<~SQL).first
      SELECT JSON_OBJECT(
        'tree_id', t.id,
        'tree_index', t.`index`,
        'branch_id', b.id,
        'branch_name', b.name,
        'branch_index', b.`index`
      )
      FROM dataset_trees t
      INNER JOIN branches b ON b.dataset_tree_id = t.id
      WHERE t.dataset_in_pool_id = #{Integer(dip_id)} AND t.head = 1 AND b.head = 1
      LIMIT 1
    SQL
  end

  def branch_rows_for_dip(services, dip_id)
    services.mysql_json_rows(sql: <<~SQL)
      SELECT JSON_OBJECT(
        'id', b.id,
        'name', b.name,
        'index', b.`index`,
        'head', b.head,
        'tree_id', t.id,
        'tree_index', t.`index`
      )
      FROM branches b
      INNER JOIN dataset_trees t ON t.id = b.dataset_tree_id
      WHERE t.dataset_in_pool_id = #{Integer(dip_id)}
      ORDER BY b.id
    SQL
  end

  def branch_entries_for_dip(services, dip_id)
    services.mysql_json_rows(sql: <<~SQL)
      SELECT JSON_OBJECT(
        'entry_id', e.id,
        'parent_entry_id', e.snapshot_in_pool_in_branch_id,
        'branch_id', b.id,
        'branch_name', b.name,
        'branch_index', b.`index`,
        'branch_head', b.head,
        'tree_id', t.id,
        'tree_index', t.`index`,
        'snapshot_in_pool_id', sip.id,
        'snapshot_id', s.id,
        'snapshot_name', s.name,
        'reference_count', sip.reference_count
      )
      FROM snapshot_in_pool_in_branches e
      INNER JOIN branches b ON b.id = e.branch_id
      INNER JOIN dataset_trees t ON t.id = b.dataset_tree_id
      INNER JOIN snapshot_in_pools sip ON sip.id = e.snapshot_in_pool_id
      INNER JOIN snapshots s ON s.id = sip.snapshot_id
      WHERE t.dataset_in_pool_id = #{Integer(dip_id)}
      ORDER BY s.id, e.id
    SQL
  end

  def zfs_branch_origin_map(node, backup_dataset_path)
    escaped = Shellwords.escape(backup_dataset_path)
    _, output = node.succeeds(
      "zfs get -H -o name,value origin -t filesystem -r #{escaped}",
      timeout: 60
    )

    output.lines.each_with_object({}) do |line, acc|
      name, origin = line.strip.split("\t", 2)
      next unless name.include?('/tree.') && name.include?('/branch-')

      acc[name] = origin
    end
  end

  def zfs_snapshot_clone_map(node, backup_dataset_path)
    escaped = Shellwords.escape(backup_dataset_path)
    _, output = node.succeeds(
      "zfs get -H -o name,value clones -t snapshot -r #{escaped}",
      timeout: 60
    )

    output.lines.each_with_object({}) do |line, acc|
      name, clones = line.strip.split("\t", 2)
      next unless name.include?('@')

      acc[name] = clones.to_s.split(',').reject { |value| value.empty? || value == '-' }
    end
  end

  def backup_topology_report(services, backup_node:, dst_dip_id:, backup_dataset_path:)
    trees = services.mysql_json_rows(sql: <<~SQL)
      SELECT JSON_OBJECT('id', id, 'index', `index`, 'head', head)
      FROM dataset_trees
      WHERE dataset_in_pool_id = #{Integer(dst_dip_id)}
      ORDER BY `index`, id
    SQL

    {
      'db' => {
        'trees' => trees,
        'branches' => branch_rows_for_dip(services, dst_dip_id),
        'entries' => branch_entries_for_dip(services, dst_dip_id)
      },
      'zfs' => {
        'origins' => zfs_branch_origin_map(backup_node, backup_dataset_path),
        'clones' => zfs_snapshot_clone_map(backup_node, backup_dataset_path)
      }
    }
  end

  def backup_dataset_exists?(backup_node, backup_dataset_path)
    backup_node.zfs_exists?(backup_dataset_path, type: 'filesystem', timeout: 30)
  end

  def normalize_backup_topology_report(report)
    StorageTopologyFixture.normalize_backup_topology_report(report)
  end

  def topology_fixture_payload(report, metadata: {}, generated_at: nil)
    StorageTopologyFixture.topology_fixture_payload(
      report,
      metadata: metadata,
      generated_at: generated_at
    )
  end

  def write_topology_fixture(path, payload)
    StorageTopologyFixture.write_topology_fixture(path, payload)
  end

  def load_topology_fixture(path)
    StorageTopologyFixture.load_topology_fixture(path)
  end

  def zfs_leaf_snapshot_names(report)
    StorageTopologyFixture.zfs_leaf_snapshot_names(report)
  end

  def db_leaf_candidate_snapshot_names(report)
    StorageTopologyFixture.db_leaf_candidate_snapshot_names(report)
  end

  def delete_order_diagnostic(report)
    StorageTopologyFixture.delete_order_diagnostic(report)
  end

  def delete_order_leaf_contract(report)
    StorageTopologyFixture.delete_order_leaf_contract(report)
  end

  def delete_order_leaf_contract_from_fixture(path)
    StorageTopologyFixture.delete_order_leaf_contract_from_fixture(path)
  end

  def validate_topology_fixture!(fixture)
    result = StorageTopologyFixture.validate_fixture(fixture)

    expect(result.fetch(:errors)).to eq([]), result.inspect
    expect(fixture.fetch('report')).to eq(result.fetch(:normalized_report))
    expect(fixture.fetch('diagnostic')).to eq(result.fetch(:diagnostic))

    contract = result.fetch(:contract)
    expected = result.fetch(:expected_leaf_sets_match)

    expect(contract.fetch('leaf_sets_match')).to eq(expected) unless expected.nil?

    contract
  end

  def fixture_failure_artifact_dir
    ENV['STORAGE_TOPOLOGY_FIXTURE_DIR'].to_s.strip
  end

  def maybe_capture_topology_fixture(
    services,
    backup_node:,
    dst_dip_id:,
    backup_dataset_path:,
    file_name:,
    metadata: {},
    generated_at: nil
  )
    base = fixture_failure_artifact_dir
    return nil if base.empty?

    capture_backup_topology_fixture(
      services,
      backup_node: backup_node,
      dst_dip_id: dst_dip_id,
      backup_dataset_path: backup_dataset_path,
      path: File.join(base, file_name),
      metadata: metadata,
      generated_at: generated_at
    )
  end

  def capture_backup_topology_fixture(
    services,
    backup_node:,
    dst_dip_id:,
    backup_dataset_path:,
    path:,
    metadata: {},
    generated_at: nil
  )
    report = backup_topology_report(
      services,
      backup_node: backup_node,
      dst_dip_id: dst_dip_id,
      backup_dataset_path: backup_dataset_path
    )
    payload = topology_fixture_payload(
      report,
      metadata: metadata,
      generated_at: generated_at
    )

    write_topology_fixture(path, payload)
    payload
  end

  def dataset_in_pool_info(services, dataset_id:, pool_id:)
    services.mysql_json_rows(sql: <<~SQL).first
      SELECT JSON_OBJECT('dataset_in_pool_id', dip.id)
      FROM dataset_in_pools dip
      WHERE dip.dataset_id = #{Integer(dataset_id)} AND dip.pool_id = #{Integer(pool_id)}
      LIMIT 1
    SQL
  end

  def dataset_record_counts(services, dataset_id:)
    services.mysql_json_rows(sql: <<~SQL).first
      SELECT JSON_OBJECT(
        'datasets', (
          SELECT COUNT(*)
          FROM datasets
          WHERE id = #{Integer(dataset_id)}
        ),
        'dataset_in_pools', (
          SELECT COUNT(*)
          FROM dataset_in_pools
          WHERE dataset_id = #{Integer(dataset_id)}
        ),
        'dataset_trees', (
          SELECT COUNT(*)
          FROM dataset_trees t
          INNER JOIN dataset_in_pools dip ON dip.id = t.dataset_in_pool_id
          WHERE dip.dataset_id = #{Integer(dataset_id)}
        ),
        'branches', (
          SELECT COUNT(*)
          FROM branches b
          INNER JOIN dataset_trees t ON t.id = b.dataset_tree_id
          INNER JOIN dataset_in_pools dip ON dip.id = t.dataset_in_pool_id
          WHERE dip.dataset_id = #{Integer(dataset_id)}
        ),
        'snapshot_in_pools', (
          SELECT COUNT(*)
          FROM snapshot_in_pools sip
          INNER JOIN dataset_in_pools dip ON dip.id = sip.dataset_in_pool_id
          WHERE dip.dataset_id = #{Integer(dataset_id)}
        ),
        'snapshot_in_pool_in_branches', (
          SELECT COUNT(*)
          FROM snapshot_in_pool_in_branches e
          INNER JOIN snapshot_in_pools sip ON sip.id = e.snapshot_in_pool_id
          INNER JOIN dataset_in_pools dip ON dip.id = sip.dataset_in_pool_id
          WHERE dip.dataset_id = #{Integer(dataset_id)}
        )
      )
    SQL
  end

  def ensure_dataset_in_pool(services, admin_user_id:, dataset_id:, pool_id:)
    info = dataset_in_pool_info(
      services,
      dataset_id: dataset_id,
      pool_id: pool_id
    )
    return info if info

    response = services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      dataset = Dataset.find(#{Integer(dataset_id)})
      pool = Pool.find(#{Integer(pool_id)})
      src = dataset.primary_dataset_in_pool!
      chain, created = TransactionChains::Dataset::Create.fire(
        pool,
        src,
        [dataset],
        label: src.label,
        properties: {}
      )
      dip = Array(created).last

      puts JSON.dump(chain_id: chain.id, dataset_in_pool_id: dip.id)
    RUBY

    services.wait_for_chain_state(response.fetch('chain_id'), state: :done)
    dataset_in_pool_info(
      services,
      dataset_id: dataset_id,
      pool_id: pool_id
    )
  end

  def chain_transactions(services, chain_id)
    services.mysql_json_rows(sql: <<~SQL)
      SELECT JSON_OBJECT(
        'id', id,
        'handle', handle,
        'node_id', node_id,
        'queue', queue,
        'depends_on_id', depends_on_id,
        'done', done,
        'status', status
      )
      FROM transactions
      WHERE transaction_chain_id = #{Integer(chain_id)}
      ORDER BY id
    SQL
  end

  def chain_failure_details(services, chain_id)
    rows = services.mysql_json_rows(sql: <<~SQL)
      SELECT JSON_OBJECT(
        'id', id,
        'handle', handle,
        'done', done,
        'status', status,
        'output', output
      )
      FROM transactions
      WHERE transaction_chain_id = #{Integer(chain_id)}
        AND (
          status = 0
          OR (
            output IS NOT NULL
            AND CHAR_LENGTH(output) > 0
            AND output <> '{}'
            AND output <> 'null'
          )
        )
      ORDER BY id
    SQL

    rows.map do |row|
      parsed = row['output'] && !row['output'].empty? ? JSON.parse(row['output']) : {}

      row.merge(
        'output' => parsed,
        'error' => parsed['error']
      )
    end
  end

  def wait_for_chain_failure_detail(services, chain_id, handle:, timeout: 60)
    deadline = Time.now + timeout

    loop do
      detail = chain_failure_details(services, chain_id).detect do |tx|
        tx.fetch('handle') == Integer(handle)
      end

      return detail if detail

      if Time.now >= deadline
        raise OsVm::TimeoutError,
              "Timed out waiting for failure detail on chain ##{chain_id} " \
              "handle=#{handle}"
      end

      sleep 1
    end
  end

  def wait_for_chain_failure_output_value(services, chain_id, handle:, path:, timeout: 60)
    keys = Array(path)
    deadline = Time.now + timeout

    loop do
      detail = wait_for_chain_failure_detail(
        services,
        chain_id,
        handle: handle,
        timeout: [deadline - Time.now, 1].max
      )
      value = keys.reduce(detail) do |memo, key|
        memo.is_a?(Hash) ? memo[key] : nil
      end

      return detail if !value.nil?

      if Time.now >= deadline
        raise OsVm::TimeoutError,
              "Timed out waiting for failure detail value on chain ##{chain_id} " \
              "handle=#{handle} path=#{keys.inspect}"
      end

      sleep 1
    end
  end

  DEPENDENCY_ERROR_PATTERNS = [
    /dependent clones/i,
    /has children/i,
    /cannot destroy/i,
    /use '-R' to destroy/i
  ].freeze

  def dependency_failure?(detail)
    payload = detail.fetch('output', {})
    text = [
      detail['error'],
      payload.is_a?(Hash) ? payload.values.map(&:to_s).join(' ') : payload.to_s
    ].compact.join(' ')

    DEPENDENCY_ERROR_PATTERNS.any? { |rx| rx.match?(text) }
  end

  def dependency_failure_details(services, chain_id)
    chain_failure_details(services, chain_id).select do |detail|
      dependency_failure?(detail)
    end
  end

  def dependency_failure_handles(details)
    details.map { |row| Integer(row.fetch('handle')) }.uniq.sort
  end

  def assert_known_dependency_failure!(services, chain_id:, allowed_handles:, diagnostic: nil)
    details = chain_failure_details(services, chain_id)
    dependency = dependency_failure_details(services, chain_id)
    handles = dependency_failure_handles(dependency)
    allowed = Array(allowed_handles).map { |handle| Integer(handle) }.sort

    expect(dependency).not_to eq([]), {
      details: details,
      diagnostic: diagnostic
    }.inspect

    expect((handles - allowed)).to eq([]), {
      details: details,
      handles: handles,
      allowed: allowed,
      diagnostic: diagnostic
    }.inspect

    details
  end

  def assert_dependency_failure_contract!(
    services,
    chain_id:,
    allowed_handles:,
    report:
  )
    details = assert_known_dependency_failure!(
      services,
      chain_id: chain_id,
      allowed_handles: allowed_handles,
      diagnostic: delete_order_leaf_contract(report)
    )

    message = details.map do |row|
      [row['handle'], row['status'], row['error']].compact.join(' | ')
    end.join("\n")

    expect(message).to match(/cannot destroy|dependent clones|has children|use '-R'/i)

    contract = delete_order_leaf_contract(report)
    expect(contract.fetch('leaf_sets_match')).to be(false), contract.inspect

    contract
  end

  STORAGE_CHAIN_STATES = {
    staged: 0,
    queued: 1,
    done: 2,
    rollbacking: 3,
    failed: 4,
    fatal: 5,
    resolved: 6
  }.freeze

  def wait_for_chain_states_local(services, chain_id, states, timeout: 300)
    expected = Array(states).map do |state|
      state.is_a?(Symbol) ? STORAGE_CHAIN_STATES.fetch(state) : Integer(state)
    end
    deadline = Time.now + timeout

    loop do
      row = services.mysql_json_rows(sql: <<~SQL).first
        SELECT JSON_OBJECT('state', state)
        FROM transaction_chains
        WHERE id = #{Integer(chain_id)}
        LIMIT 1
      SQL
      current = row && Integer(row.fetch('state'))

      return current if current && expected.include?(current)

      if Time.now >= deadline
        raise OsVm::TimeoutError,
              "Timed out waiting for chain ##{chain_id} " \
              "state in #{states.inspect}"
      end

      sleep 1
    end
  end

  def wait_for_tx_handle_started(services, chain_id, handle)
    wait_until_block_succeeds(name: "chain #{chain_id} handle #{handle} started") do
      services.mysql_scalar(sql: <<~SQL).to_i > 0
        SELECT COUNT(*)
        FROM transactions
        WHERE transaction_chain_id = #{Integer(chain_id)}
          AND handle = #{Integer(handle)}
          AND started_at IS NOT NULL
      SQL
    end
  end

  def failed_chain_transactions(services, chain_id)
    services.mysql_json_rows(sql: <<~SQL)
      SELECT JSON_OBJECT(
        'id', id,
        'handle', handle,
        'done', done,
        'status', status,
        'queue', queue
      )
      FROM transactions
      WHERE transaction_chain_id = #{Integer(chain_id)}
        AND status = 0
      ORDER BY id
    SQL
  end

  def chain_port_reservations(services, chain_id)
    services.mysql_json_rows(sql: <<~SQL)
      SELECT JSON_OBJECT(
        'id', id,
        'node_id', node_id,
        'addr', addr,
        'port', port
      )
      FROM port_reservations
      WHERE transaction_chain_id = #{Integer(chain_id)}
      ORDER BY id
    SQL
  end

  def current_history_id(services, dataset_id)
    services.mysql_scalar(sql: "SELECT current_history_id FROM datasets WHERE id = #{Integer(dataset_id)}").to_i
  end

  def wait_for_snapshot_names(
    services,
    dip_id:,
    include_names: [],
    exclude_names: [],
    timeout: 60
  )
    deadline = Time.now + timeout

    loop do
      names = snapshot_rows_for_dip(services, dip_id).map do |row|
        row.fetch('name')
      end

      include_ok = Array(include_names).all? do |name|
        names.include?(name)
      end
      exclude_ok = Array(exclude_names).none? do |name|
        names.include?(name)
      end

      return names if include_ok && exclude_ok

      if Time.now >= deadline
        raise OsVm::TimeoutError,
              "Timed out waiting for snapshots on dip=#{dip_id}"
      end

      sleep 1
    end
  end

  def set_snapshot_retention(services, dip_id:, min_snapshots:, max_snapshots:, snapshot_max_age:)
    services.mysql_raw(sql: <<~SQL)
      UPDATE dataset_in_pools
      SET min_snapshots = #{Integer(min_snapshots)},
          max_snapshots = #{Integer(max_snapshots)},
          snapshot_max_age = #{Integer(snapshot_max_age)}
      WHERE id = #{Integer(dip_id)}
    SQL
  end

  def create_snapshot(services, dataset_id:, dip_id:, label:)
    _, output = services.vpsadminctl.succeeds(
      args: ['dataset.snapshot', 'create', dataset_id.to_s],
      parameters: { label: label }
    )

    snapshot = output.fetch('snapshot')
    services.wait_for_snapshot_in_pool(dip_id, snapshot.fetch('id'))
    snapshot.merge(
      snapshot_rows_for_dip(services, dip_id).find { |row| row.fetch('id') == snapshot.fetch('id') }
    )
  end

  def create_snapshot_download(services, snapshot_id:, format:, from_snapshot_id: nil, send_mail: false)
    parameters = {
      snapshot: snapshot_id,
      format: format,
      send_mail: send_mail
    }
    parameters[:from_snapshot] = from_snapshot_id if from_snapshot_id

    _, output = services.vpsadminctl.succeeds(
      args: %w[snapshot_download create],
      parameters: parameters
    )

    output.fetch('snapshot_download').merge(
      'chain_id' => output.fetch('_meta').fetch('action_state_id')
    )
  end

  def delete_snapshot_download(services, download_id:)
    _, output = services.vpsadminctl.succeeds(
      args: ['snapshot_download', 'delete', download_id.to_s]
    )

    {
      'chain_id' => output.fetch('_meta').fetch('action_state_id')
    }
  end

  def snapshot_download_row(services, download_id)
    services.api_ruby_json(code: <<~RUBY)
      dl = SnapshotDownload.includes(pool: { node: { location: :environment } }).find_by(
        id: #{Integer(download_id)}
      )

      if dl.nil?
        puts JSON.dump(nil)
      else
        puts JSON.dump(
          id: dl.id,
          snapshot_id: dl.snapshot_id,
          from_snapshot_id: dl.from_snapshot_id,
          pool_id: dl.pool_id,
          node_id: dl.pool.node_id,
          secret_key: dl.secret_key,
          file_name: dl.file_name,
          size: dl.size,
          sha256sum: dl.sha256sum,
          format: dl.format,
          confirmed: dl.confirmed,
          url: dl.url
        )
      end
    RUBY
  end

  def wait_for_snapshot_download_ready(services, download_id, timeout: 300)
    deadline = Time.now + timeout

    loop do
      row = snapshot_download_row(services, download_id)

      return row if row &&
                    row.fetch('confirmed') == 'confirmed' &&
                    !row.fetch('sha256sum').to_s.empty? &&
                    !row['size'].nil?

      if Time.now >= deadline
        raise OsVm::TimeoutError,
              "Timed out waiting for snapshot download ##{download_id} to become ready"
      end

      sleep 1
    end
  end

  def wait_for_snapshot_download_deleted(services, download_id, timeout: 300)
    deadline = Time.now + timeout

    loop do
      return true if snapshot_download_row(services, download_id).nil?

      if Time.now >= deadline
        raise OsVm::TimeoutError,
              "Timed out waiting for snapshot download ##{download_id} to be deleted"
      end

      sleep 1
    end
  end

  def download_secret_dir_path(pool_fs:, secret_key:)
    File.join('/', pool_fs, 'vpsadmin/download', secret_key)
  end

  def download_file_path(pool_fs:, secret_key:, file_name:)
    File.join(download_secret_dir_path(pool_fs: pool_fs, secret_key: secret_key), file_name)
  end

  def gzip_stream_listing(node, file_path)
    _, output = node.succeeds(
      "tar -tzf #{Shellwords.escape(file_path)}",
      timeout: 120
    )
    output.to_s.lines.map(&:strip).reject(&:empty?)
  end

  def zstreamdump_output(node, file_path)
    _, output = node.succeeds(
      "bash -lc #{Shellwords.escape("gzip -dc #{Shellwords.escape(file_path)} | zstreamdump -v 2>&1")}",
      timeout: 300
    )
    output
  end

  def zfs_guid(node, dataset_path)
    _, output = node.succeeds(
      "zfs get -H -p -o value guid #{Shellwords.escape(dataset_path)}",
      timeout: 60
    )
    Integer(output.strip, 10).to_s(16)
  end

  def fire_backup(services, admin_user_id:, src_dip_id:, dst_dip_id:)
    response = services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      src = DatasetInPool.find(#{src_dip_id})
      dst = DatasetInPool.find(#{dst_dip_id})
      chain, = TransactionChains::Dataset::Backup.fire(src, dst)

      puts JSON.dump(chain_id: chain.id)
    RUBY

    final_state = wait_for_chain_states_local(
      services,
      response.fetch('chain_id'),
      %i[done failed fatal resolved],
      timeout: 1200
    )
    expect(final_state).to eq(services.class::CHAIN_STATES[:done]), {
      chain_id: response.fetch('chain_id'),
      final_state: final_state,
      failure_details: chain_failure_details(services, response.fetch('chain_id'))
    }.inspect
    response
  end

  def fire_backup_async(services, admin_user_id:, src_dip_id:, dst_dip_id:)
    services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      src = DatasetInPool.find(#{src_dip_id})
      dst = DatasetInPool.find(#{dst_dip_id})
      chain, = TransactionChains::Dataset::Backup.fire(src, dst)

      puts JSON.dump(chain_id: chain.id)
    RUBY
  end

  def create_and_backup_snapshot(services, admin_user_id:, dataset_id:, src_dip_id:, dst_dip_id:, label:)
    snapshot = create_snapshot(
      services,
      dataset_id: dataset_id,
      dip_id: src_dip_id,
      label: label
    )
    response = fire_backup(
      services,
      admin_user_id: admin_user_id,
      src_dip_id: src_dip_id,
      dst_dip_id: dst_dip_id
    )

    snapshot.merge('chain_id' => response.fetch('chain_id'))
  end

  def create_descendant_dataset(services, admin_user_id:, parent_dataset_id:, name:, pool_fs:, refquota: 10_240)
    response = services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      parent = Dataset.find(#{Integer(parent_dataset_id)})
      chain, dataset = VpsAdmin::API::Operations::Dataset::Create.run(
        #{name.inspect},
        parent,
        automount: false,
        properties: { refquota: #{Integer(refquota)} }
      )

      puts JSON.dump(
        chain_id: chain.id,
        dataset_id: dataset.id,
        dip_id: dataset.primary_dataset_in_pool!.id,
        full_name: dataset.full_name
      )
    RUBY

    services.wait_for_chain_state(response.fetch('chain_id'), state: :done)

    response.merge(
      'dataset_path' => "#{pool_fs}/#{response.fetch('full_name')}"
    )
  end

  def create_top_level_dataset(services, admin_user_id:, pool_id:, dataset_name:, refquota: 10_240)
    response = services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      user = User.find(#{Integer(admin_user_id)})
      pool = Pool.find(#{Integer(pool_id)})
      dataset = Dataset.new(
        name: #{dataset_name.inspect},
        user: user,
        user_editable: true,
        user_create: true,
        user_destroy: true,
        confirmed: Dataset.confirmed(:confirm_create)
      )
      chain, created = TransactionChains::Dataset::Create.fire(
        pool,
        nil,
        [dataset],
        automount: false,
        properties: { refquota: #{Integer(refquota)} },
        user: user,
        label: #{dataset_name.inspect}
      )
      dip = Array(created).last

      puts JSON.dump(
        chain_id: chain.id,
        dataset_id: dataset.id,
        dataset_in_pool_id: dip.id,
        dataset_full_name: dataset.full_name
      )
    RUBY

    services.wait_for_chain_state(response.fetch('chain_id'), state: :done)
    response
  end

  def create_primary_dataset(services, primary_node:, admin_user_id:, primary_node_id:, dataset_name:, primary_pool_fs:,
                             refquota: 10_240)
    primary_pool = create_pool(
      services,
      node_id: primary_node_id,
      label: "#{dataset_name}-primary",
      filesystem: primary_pool_fs,
      role: 'primary'
    )

    wait_for_pool_online(services, primary_pool.fetch('id'))

    info = create_top_level_dataset(
      services,
      admin_user_id: admin_user_id,
      pool_id: primary_pool.fetch('id'),
      dataset_name: dataset_name,
      refquota: refquota
    )

    primary_dataset_path = "#{primary_pool_fs}/#{info.fetch('dataset_full_name')}"

    wait_until_block_succeeds(name: "primary dataset #{primary_dataset_path} exists") do
      primary_node.zfs_exists?(primary_dataset_path, type: 'filesystem', timeout: 30)
    end

    {
      'primary_pool_id' => primary_pool.fetch('id'),
      'dataset_id' => info.fetch('dataset_id'),
      'src_dip_id' => info.fetch('dataset_in_pool_id'),
      'dataset_full_name' => info.fetch('dataset_full_name'),
      'primary_dataset_path' => primary_dataset_path
    }
  end

  def export_row(services, export_id)
    row = services.mysql_json_rows(sql: <<~SQL).first
      SELECT JSON_OBJECT(
        'id', e.id,
        'dataset_in_pool_id', e.dataset_in_pool_id,
        'pool_id', dip.pool_id,
        'node_id', p.node_id,
        'path', e.path,
        'enabled', e.enabled
      )
      FROM exports e
      INNER JOIN dataset_in_pools dip ON dip.id = e.dataset_in_pool_id
      INNER JOIN pools p ON p.id = dip.pool_id
      WHERE e.id = #{Integer(export_id)}
      LIMIT 1
    SQL

    return nil if row.nil?

    row.merge(
      'enabled' => row.fetch('enabled') == true || row.fetch('enabled').to_i == 1
    )
  end

  def ensure_private_export_network_with_ips(services, admin_user_id:, dataset_id:, count: 1)
    services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      dataset = Dataset.find(#{Integer(dataset_id)})
      location = dataset.primary_dataset_in_pool!.pool.node.location

      network = Network.find_or_initialize_by(address: '198.51.100.0', prefix: 24)
      network.assign_attributes(
        label: 'Storage Export Net',
        ip_version: 4,
        role: :private_access,
        managed: true,
        split_access: :no_access,
        split_prefix: 32,
        purpose: :export,
        primary_location: location
      )
      network.save! if network.changed?

      loc_net = LocationNetwork.find_or_initialize_by(location: location, network: network)
      loc_net.assign_attributes(
        primary: true,
        priority: 10,
        autopick: true,
        userpick: true
      )
      loc_net.save! if loc_net.changed?

      seeded_ips = []

      #{Integer(count)}.times do |i|
        addr = '198.51.100.' + (10 + i).to_s
        ip = IpAddress.find_by(ip_addr: addr)

        if ip.nil?
          ip = IpAddress.register(
            IPAddress.parse(addr + '/' + network.split_prefix.to_s),
            network: network,
            user: nil,
            location: location,
            prefix: network.split_prefix,
            size: 1
          )
        end

        seeded_ips << {
          id: ip.id,
          addr: ip.ip_addr
        }
      end

      puts JSON.dump(
        network_id: network.id,
        location_id: location.id,
        ip_addresses: seeded_ips
      )
    RUBY
  end

  def create_export(services, admin_user_id:, dataset_id:, all_vps: false, enabled: true)
    response = services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      dataset = Dataset.find(#{Integer(dataset_id)})
      chain, export = VpsAdmin::API::Operations::Export::Create.run(
        dataset,
        all_vps: #{all_vps ? 'true' : 'false'},
        rw: true,
        sync: true,
        subtree_check: false,
        root_squash: false,
        threads: 8,
        enabled: #{enabled ? 'true' : 'false'}
      )

      puts JSON.dump(chain_id: chain.id, export_id: export.id)
    RUBY

    services.wait_for_chain_state(response.fetch('chain_id'), state: :done)
    export_row(services, response.fetch('export_id')).merge(
      'chain_id' => response.fetch('chain_id')
    )
  end

  def add_export_host(services, admin_user_id:, export_id:, ip_address_id:)
    response = services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      export = Export.find(#{Integer(export_id)})
      ip_address = IpAddress.find(#{Integer(ip_address_id)})
      chain, host = VpsAdmin::API::Operations::Export::AddHost.run(
        export,
        ip_address: ip_address
      )

      puts JSON.dump(chain_id: chain.id, export_host_id: host.id)
    RUBY

    services.wait_for_chain_state(response.fetch('chain_id'), state: :done)
    response
  end

  def dataset_migrate(services, dataset_id:, pool_id:, rsync: false, restart_vps: false, cleanup_data: true,
                      send_mail: false, block: true)
    _, output = services.vpsadminctl.succeeds(
      args: ['dataset', 'migrate', dataset_id.to_s],
      opts: {
        block: block
      },
      parameters: {
        pool: pool_id,
        rsync: rsync,
        restart_vps: restart_vps,
        cleanup_data: cleanup_data,
        optional_maintenance_window: true,
        send_mail: send_mail
      }
    )

    {
      'chain_id' => output.fetch('_meta').fetch('action_state_id')
    }
  end

  def vps_migrate(services, vps_id:, node_id:, cleanup_data: true, no_start: false, skip_start: false,
                  send_mail: false)
    _, output = services.vpsadminctl.succeeds(
      args: ['vps', 'migrate', vps_id.to_s],
      parameters: {
        node: node_id,
        maintenance_window: false,
        cleanup_data: cleanup_data,
        no_start: no_start,
        skip_start: skip_start,
        send_mail: send_mail
      }
    )

    {
      'chain_id' => output.fetch('_meta').fetch('action_state_id')
    }
  end

  def hard_delete_vps(services, admin_user_id:, vps_id:, reason: 'storage test hard delete')
    response = services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      vps = Vps.unscoped.find(#{Integer(vps_id)})
      chain = vps.set_object_state(
        :hard_delete,
        user: User.current,
        reason: #{reason.inspect}
      )

      puts JSON.dump(chain_id: chain.id)
    RUBY

    wait_for_chain_states_local(
      services,
      response.fetch('chain_id'),
      %i[done failed fatal resolved]
    )
    response
  end

  def vps_unscoped_row(services, vps_id)
    services.mysql_json_rows(sql: <<~SQL).first
      SELECT JSON_OBJECT(
        'id', id,
        'object_state', CASE object_state
          WHEN 0 THEN 'active'
          WHEN 1 THEN 'suspended'
          WHEN 2 THEN 'soft_delete'
          WHEN 3 THEN 'hard_delete'
          WHEN 4 THEN 'deleted'
        END,
        'object_state_id', object_state,
        'dataset_in_pool_id', dataset_in_pool_id,
        'user_namespace_map_id', user_namespace_map_id
      )
      FROM vpses
      WHERE id = #{Integer(vps_id)}
      LIMIT 1
    SQL
  end

  def backup_head_counts(services, dataset_id:)
    services.mysql_json_rows(sql: <<~SQL).first
      SELECT JSON_OBJECT(
        'tree_heads', (
          SELECT COUNT(*)
          FROM dataset_trees t
          INNER JOIN dataset_in_pools dip ON dip.id = t.dataset_in_pool_id
          INNER JOIN pools p ON p.id = dip.pool_id
          WHERE dip.dataset_id = #{Integer(dataset_id)}
            AND p.role = 2
            AND t.head = 1
        ),
        'branch_heads', (
          SELECT COUNT(*)
          FROM branches b
          INNER JOIN dataset_trees t ON t.id = b.dataset_tree_id
          INNER JOIN dataset_in_pools dip ON dip.id = t.dataset_in_pool_id
          INNER JOIN pools p ON p.id = dip.pool_id
          WHERE dip.dataset_id = #{Integer(dataset_id)}
            AND p.role = 2
            AND b.head = 1
        )
      )
    SQL
  end

  def dataset_subtree_ids(services, root_dataset_id)
    root_id = Integer(root_dataset_id)

    services.mysql_json_rows(sql: <<~SQL).map { |row| row.fetch('id') }
      SELECT JSON_OBJECT('id', id)
      FROM datasets
      WHERE id = #{root_id}
         OR ancestry = #{root_id.to_s.inspect}
         OR ancestry LIKE #{("#{root_id}/%").inspect}
      ORDER BY id
    SQL
  end

  def build_repeated_rollback_topology(services, admin_user_id:, dataset_id:, src_dip_id:, dst_dip_id:, vps_id: nil,
                                       label_prefix: 'repeated')
    snapshots = {}

    %w[s1 s2 s3 s4 s5].each do |name|
      snapshots[name] = create_and_backup_snapshot(
        services,
        admin_user_id: admin_user_id,
        dataset_id: dataset_id,
        src_dip_id: src_dip_id,
        dst_dip_id: dst_dip_id,
        label: "#{label_prefix}-#{name}"
      )
    end

    rollback_s3 = rollback_dataset_to_snapshot(
      services,
      dataset_id: dataset_id,
      snapshot_id: snapshots.fetch('s3').fetch('id')
    )
    services.wait_for_chain_state(rollback_s3.fetch('chain_id'), state: :done)
    wait_for_vps_running(services, vps_id) if vps_id

    %w[s6 s7].each do |name|
      snapshots[name] = create_and_backup_snapshot(
        services,
        admin_user_id: admin_user_id,
        dataset_id: dataset_id,
        src_dip_id: src_dip_id,
        dst_dip_id: dst_dip_id,
        label: "#{label_prefix}-#{name}"
      )
    end

    rollback_s2 = rollback_dataset_to_snapshot(
      services,
      dataset_id: dataset_id,
      snapshot_id: snapshots.fetch('s2').fetch('id')
    )
    services.wait_for_chain_state(rollback_s2.fetch('chain_id'), state: :done)
    wait_for_vps_running(services, vps_id) if vps_id

    snapshots['s8'] = create_and_backup_snapshot(
      services,
      admin_user_id: admin_user_id,
      dataset_id: dataset_id,
      src_dip_id: src_dip_id,
      dst_dip_id: dst_dip_id,
      label: "#{label_prefix}-s8"
    )

    {
      'snapshots' => snapshots,
      'rollback_chain_ids' => [
        rollback_s3.fetch('chain_id'),
        rollback_s2.fetch('chain_id')
      ]
    }
  end

  def build_complex_multi_tree_topology(services, admin_user_id:, dataset_id:, src_dip_id:, dst_dip_id:, vps_id: nil,
                                        label_prefix: 'complex')
    snapshots = {}

    %w[s1 s2 s3 s4 s5].each do |name|
      snapshots[name] = create_and_backup_snapshot(
        services,
        admin_user_id: admin_user_id,
        dataset_id: dataset_id,
        src_dip_id: src_dip_id,
        dst_dip_id: dst_dip_id,
        label: "#{label_prefix}-#{name}"
      )
    end

    rollback_s3 = rollback_dataset_to_snapshot(
      services,
      dataset_id: dataset_id,
      snapshot_id: snapshots.fetch('s3').fetch('id')
    )
    services.wait_for_chain_state(rollback_s3.fetch('chain_id'), state: :done)
    wait_for_vps_running(services, vps_id) if vps_id

    %w[s6 s7].each do |name|
      snapshots[name] = create_and_backup_snapshot(
        services,
        admin_user_id: admin_user_id,
        dataset_id: dataset_id,
        src_dip_id: src_dip_id,
        dst_dip_id: dst_dip_id,
        label: "#{label_prefix}-#{name}"
      )
    end

    reinstall =
      if vps_id
        reinstall_vps(
          services,
          admin_user_id: admin_user_id,
          vps_id: vps_id
        )
      else
        reset_standalone_dataset(
          services,
          admin_user_id: admin_user_id,
          src_dip_id: src_dip_id
        )
      end
    services.wait_for_chain_state(reinstall.fetch('chain_id'), state: :done)

    wait_until_block_succeeds(name: "local snapshots removed after reinstall for #{label_prefix}") do
      snapshot_rows_for_dip(services, src_dip_id).empty?
    end

    %w[s8 s9].each do |name|
      snapshots[name] = create_and_backup_snapshot(
        services,
        admin_user_id: admin_user_id,
        dataset_id: dataset_id,
        src_dip_id: src_dip_id,
        dst_dip_id: dst_dip_id,
        label: "#{label_prefix}-#{name}"
      )
    end

    rollback_s2 = rollback_dataset_to_snapshot(
      services,
      dataset_id: dataset_id,
      snapshot_id: snapshots.fetch('s2').fetch('id')
    )
    services.wait_for_chain_state(rollback_s2.fetch('chain_id'), state: :done)
    wait_for_vps_running(services, vps_id) if vps_id

    snapshots['s10'] = create_and_backup_snapshot(
      services,
      admin_user_id: admin_user_id,
      dataset_id: dataset_id,
      src_dip_id: src_dip_id,
      dst_dip_id: dst_dip_id,
      label: "#{label_prefix}-s10"
    )

    {
      'snapshots' => snapshots,
      'reinstall_chain_id' => reinstall.fetch('chain_id'),
      'rollback_chain_ids' => [
        rollback_s3.fetch('chain_id'),
        rollback_s2.fetch('chain_id')
      ]
    }
  end

  def rollback_dataset_to_snapshot(services, dataset_id:, snapshot_id:)
    _, output = services.vpsadminctl.succeeds(
      args: ['dataset.snapshot', 'rollback', dataset_id.to_s, snapshot_id.to_s]
    )

    {
      'chain_id' => output.dig('_meta', 'action_state_id') || output.dig('response', '_meta', 'action_state_id'),
      'output' => output
    }
  end

  def dataset_mountpoint(node, dataset_path)
    escaped = Shellwords.escape(dataset_path)
    node.succeeds("zfs mount #{escaped} >/dev/null 2>&1 || true", timeout: 60)
    _, output = node.succeeds("zfs get -H -o value mountpoint #{escaped}", timeout: 60)
    output.strip
  end

  def find_dataset_path_on_node(node, dataset_full_name, timeout: 60)
    _, output = node.succeeds('zfs list -H -o name -t filesystem', timeout: timeout)
    suffix = "/#{dataset_full_name}"
    matches = output.to_s.lines.map(&:strip).reject(&:empty?).select do |name|
      name.end_with?(suffix)
    end

    if matches.empty?
      raise "Unable to find dataset with suffix #{suffix} on #{node.name}"
    elsif matches.size > 1
      raise "Found multiple datasets with suffix #{suffix} on #{node.name}: #{matches.inspect}"
    end

    matches.first
  end

  def write_dataset_text(node, dataset_path:, relative_path:, content:)
    mountpoint = dataset_mountpoint(node, dataset_path)
    full_path = File.join(mountpoint, relative_path)
    node.succeeds("mkdir -p #{Shellwords.escape(File.dirname(full_path))}", timeout: 60)
    node.succeeds("cat > #{Shellwords.escape(full_path)} <<'EOF'\n#{content}EOF", timeout: 60)
    content
  end

  def read_dataset_text(node, dataset_path:, relative_path:)
    mountpoint = dataset_mountpoint(node, dataset_path)
    full_path = File.join(mountpoint, relative_path)
    _, output = node.succeeds("cat #{Shellwords.escape(full_path)}", timeout: 60)
    output
  end

  def write_dataset_payload(node, dataset_path:, relative_path:, mib:)
    mountpoint = dataset_mountpoint(node, dataset_path)
    full_path = File.join(mountpoint, relative_path)
    node.succeeds("mkdir -p #{Shellwords.escape(File.dirname(full_path))}", timeout: 60)
    node.succeeds(
      "dd if=/dev/urandom of=#{Shellwords.escape(full_path)} bs=1M count=#{Integer(mib)} status=none conv=fsync",
      timeout: 900
    )
    _, output = node.succeeds("sha256sum #{Shellwords.escape(full_path)}", timeout: 60)
    output.split.first
  end

  def file_checksum(node, dataset_path:, relative_path:)
    mountpoint = dataset_mountpoint(node, dataset_path)
    full_path = File.join(mountpoint, relative_path)
    _, output = node.succeeds("sha256sum #{Shellwords.escape(full_path)}", timeout: 60)
    output.split.first
  end

  def reinstall_vps(services, admin_user_id:, vps_id:, os_template_id: 1)
    services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      vps = Vps.find(#{vps_id})
      template = OsTemplate.find(#{os_template_id})
      chain, = TransactionChains::Vps::Reinstall.fire(vps, template, {})

      puts JSON.dump(chain_id: chain.id)
    RUBY
  end

  def reset_standalone_dataset(services, admin_user_id:, src_dip_id:)
    services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      unless defined?(::TestStandaloneDatasetReset)
        class ::TestStandaloneDatasetReset < ::TransactionChain
          label 'Test standalone dataset reset'

          def link_chain(dataset_in_pool)
            lock(dataset_in_pool)
            concerns(:affect, [dataset_in_pool.dataset.class.name, dataset_in_pool.dataset_id])

            dataset_in_pool.snapshot_in_pools.order(:id).each do |sip|
              use_chain(TransactionChains::SnapshotInPool::Destroy, args: sip)
            end

            use_chain(TransactionChains::DatasetInPool::DetachBackupHeads, args: dataset_in_pool)

            append_t(Transactions::Utils::NoOp, args: dataset_in_pool.pool.node_id) do |t|
              t.increment(dataset_in_pool.dataset, 'current_history_id')
            end
          end
        end
      end

      dip = DatasetInPool.find(#{src_dip_id})
      chain, = TestStandaloneDatasetReset.fire(dip)

      puts JSON.dump(chain_id: chain.id)
    RUBY
  end

  def wait_for_recv_mbuffer(node, port)
    wait_until_block_succeeds(name: "recv mbuffer on #{node.name}:#{port}") do
      node.succeeds("pgrep -fa '[m]buffer .* -I .*#{Integer(port)}( |$)'", timeout: 10)
      true
    end
  end

  def wait_for_mbuffer_on_port(node, port)
    wait_until_block_succeeds(name: "mbuffer on #{node.name} for port #{port}") do
      node.succeeds("pgrep -fa '[m]buffer .*#{Integer(port)}( |$)'", timeout: 10)
      true
    end
  end

  def kill_mbuffer_on_port(node, port)
    node.succeeds("pkill -TERM -f '[m]buffer .*#{Integer(port)}( |$)'", timeout: 30)
  end

  def wait_for_send_mbuffer(node)
    wait_until_block_succeeds(name: "send mbuffer on #{node.name}") do
      node.succeeds("pgrep -fa '[m]buffer .* -O '", timeout: 10)
      true
    end
  end

  def kill_send_mbuffer(node)
    node.succeeds("pkill -TERM -f '[m]buffer .* -O '", timeout: 30)
  end

  def install_faulty_mbuffer(node, path:, fail_after_bytes:)
    script = <<~RUBY
      #!/usr/bin/env ruby
      # frozen_string_literal: true

      require 'socket'

      FAIL_AFTER = #{Integer(fail_after_bytes)}

      def parse_args(argv)
        args = argv.dup
        options = {}

        until args.empty?
          arg = args.shift

          case arg
          when '-O'
            host, port = args.shift.split(':', 2)
            options[:mode] = :send
            options[:host] = host
            options[:port] = Integer(port)
          when /\\A-O(.+)\\z/
            host, port = Regexp.last_match(1).split(':', 2)
            options[:mode] = :send
            options[:host] = host
            options[:port] = Integer(port)
          when '-I'
            options[:mode] = :recv
            options[:port] = Integer(args.shift)
          when /\\A-I(.+)\\z/
            options[:mode] = :recv
            options[:port] = Integer(Regexp.last_match(1))
          when '-l'
            options[:log_file] = args.shift
          when /\\A-l(.+)\\z/
            options[:log_file] = Regexp.last_match(1)
          when '-s', '-m', '-P', '-W'
            args.shift
          else
            # Ignore compatibility flags such as -q or inline-valued options.
          end
        end

        options
      end

      def log(log_file, message)
        return unless log_file

        File.open(log_file, 'a') do |f|
          f.puts(message)
        end
      rescue StandardError
        nil
      end

      def fail_send(host, port, log_file)
        socket = TCPSocket.new(host, port)
        transferred = 0

        loop do
          chunk = STDIN.readpartial(16 * 1024)
          remaining = FAIL_AFTER - transferred
          break if remaining <= 0

          payload = chunk.byteslice(0, remaining)
          socket.write(payload)
          transferred += payload.bytesize

          next unless transferred >= FAIL_AFTER

          log(log_file, "faulty-mbuffer send abort after \#{transferred} bytes")
          exit 1
        rescue EOFError
          break
        end

        socket.close
        exit 0
      end

      def fail_recv(port, log_file)
        server = TCPServer.new('0.0.0.0', port)
        socket = server.accept
        transferred = 0
        $stdout.sync = true

        loop do
          chunk = socket.readpartial(16 * 1024)
          remaining = FAIL_AFTER - transferred
          break if remaining <= 0

          payload = chunk.byteslice(0, remaining)
          STDOUT.write(payload)
          transferred += payload.bytesize

          next unless transferred >= FAIL_AFTER

          STDOUT.flush
          log(log_file, "faulty-mbuffer recv abort after \#{transferred} bytes")
          exit 1
        rescue EOFError
          break
        end

        socket.close
        server.close
        exit 0
      end

      options = parse_args(ARGV)

      case options.fetch(:mode)
      when :send
        fail_send(options.fetch(:host), options.fetch(:port), options[:log_file])
      when :recv
        fail_recv(options.fetch(:port), options[:log_file])
      end
    RUBY

    node.succeeds(<<~SH, timeout: 60)
      cat > #{Shellwords.escape(path)} <<'RUBY'
      #{script}
      RUBY
      chmod 755 #{Shellwords.escape(path)}
    SH
  end

  def set_mbuffer_command(node, direction:, command:)
    node.succeeds(
      "nodectl set config mbuffer.#{direction}.command=#{Shellwords.escape(command)}",
      timeout: 60
    )
  end

  def reset_mbuffer_command(node, direction:)
    set_mbuffer_command(node, direction: direction, command: 'mbuffer')
  end

  def install_switchable_rsync(node, path:, marker_path:)
    script = <<~SH
      #!/usr/bin/env bash
      set -euo pipefail

      if [ -e #{Shellwords.escape(marker_path)} ]; then
        echo "faulty rsync triggered by #{marker_path}" >&2
        exit 1
      fi

      exec rsync "$@"
    SH

    node.succeeds(<<~CMD, timeout: 60)
      cat > #{Shellwords.escape(path)} <<'SH'
      #{script}
      SH
      chmod 755 #{Shellwords.escape(path)}
    CMD
  end

  def install_counting_rsync(node, path:, counter_path:, fail_on_invocation:)
    script = <<~SH
      #!/usr/bin/env bash
      set -euo pipefail

      count=0
      if [ -f #{Shellwords.escape(counter_path)} ]; then
        count="$(cat #{Shellwords.escape(counter_path)})"
      fi

      count="$((count + 1))"
      printf '%s' "$count" > #{Shellwords.escape(counter_path)}

      if [ "$count" -ge #{Integer(fail_on_invocation)} ]; then
        echo "faulty rsync invocation $count" >&2
        exit 1
      fi

      exec rsync "$@"
    SH

    node.succeeds(<<~CMD, timeout: 60)
      cat > #{Shellwords.escape(path)} <<'SH'
      #{script}
      SH
      chmod 755 #{Shellwords.escape(path)}
    CMD
  end

  def set_rsync_command(node, command:)
    node.succeeds(
      "nodectl set config bin.rsync=#{Shellwords.escape(command)}",
      timeout: 60
    )
  end

  def reset_rsync_command(node)
    set_rsync_command(node, command: 'rsync')
  end

  def block_tcp_port(node, port)
    node.succeeds(
      "iptables -I INPUT -p tcp --dport #{Integer(port)} -j REJECT --reject-with tcp-reset",
      timeout: 60
    )
  end

  def unblock_tcp_port(node, port)
    node.succeeds(
      "iptables -D INPUT -p tcp --dport #{Integer(port)} -j REJECT --reject-with tcp-reset || true",
      timeout: 60
    )
  end

  def rollback_dataset_exists?(node, dataset_path)
    node.zfs_exists?("#{dataset_path}.rollback", type: 'filesystem', timeout: 30)
  end

  def snapshot_exists?(node, dataset_path, snapshot_name)
    node.zfs_exists?("#{dataset_path}@#{snapshot_name}", type: 'snapshot', timeout: 30)
  end

  def grep_nodectld_log(node, pattern)
    _, output = node.succeeds(
      "grep -F #{Shellwords.escape(pattern)} /var/log/nodectld",
      timeout: 60
    )
    output
  end

  def destroy_backup_dataset(services, admin_user_id:, dip_id:)
    services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      dip = DatasetInPool.find(#{dip_id})
      chain, = TransactionChains::DatasetInPool::Destroy.fire(dip, recursive: true)

      puts JSON.dump(chain_id: chain.id)
    RUBY
  end

  def destroy_snapshot_in_pool(services, admin_user_id:, sip_id:)
    response = services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      sip = SnapshotInPool.find(#{Integer(sip_id)})
      target = sip.snapshot_in_pool_in_branches.order(:id).take || sip
      chain, = TransactionChains::SnapshotInPool::Destroy.fire(target)

      puts JSON.dump(chain_id: chain.id)
    RUBY

    wait_for_chain_states_local(
      services,
      response.fetch('chain_id'),
      %i[done failed fatal resolved]
    )
    response
  end

  def destroy_dataset(services, admin_user_id:, dataset_id:)
    services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      ds = Dataset.find(#{Integer(dataset_id)})
      chain, = TransactionChains::Dataset::Destroy.fire(ds, nil, nil, nil)

      puts JSON.dump(chain_id: chain.id)
    RUBY
  end

  def rotate_dataset(services, admin_user_id:, dip_id:)
    response = services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      dip = DatasetInPool.find(#{dip_id})
      begin
        chain, = TransactionChains::Dataset::Rotate.fire(dip)
        puts JSON.dump(chain_id: chain.id, empty: false)
      rescue RuntimeError => e
        raise unless e.message == 'empty'

        puts JSON.dump(chain_id: nil, empty: true, error: e.message)
      end
    RUBY

    return response if response.fetch('empty', false)

    wait_for_chain_states_local(
      services,
      response.fetch('chain_id'),
      %i[done failed fatal resolved]
    )
    response
  end

  def wait_for_vps_running(services, vps_id)
    wait_until_block_succeeds(name: "VPS #{vps_id} running") do
      _, output = services.vpsadminctl.succeeds(args: ['vps', 'show', vps_id.to_s])
      output.fetch('vps').fetch('is_running')
    end
  end

  def wait_for_vps_on_node(services, vps_id:, node_id:, running: nil, timeout: 300)
    deadline = Time.now + timeout

    loop do
      _, output = services.vpsadminctl.succeeds(args: ['vps', 'show', vps_id.to_s])
      vps = output.fetch('vps')

      node_ok = vps.fetch('node').fetch('id') == Integer(node_id)
      running_ok = running.nil? || vps.fetch('is_running') == running

      return vps if node_ok && running_ok

      if Time.now >= deadline
        raise OsVm::TimeoutError,
              "Timed out waiting for VPS #{vps_id} on node #{node_id} running=#{running.inspect}"
      end

      sleep 1
    end
  end

  def branch_dataset_path(pool_fs, dataset_full_name, branch_row)
    tree_index = branch_row.fetch('tree_index')
    branch_name = branch_row.key?('branch_name') ? branch_row.fetch('branch_name') : branch_row.fetch('name')
    branch_index = branch_row.key?('branch_index') ? branch_row.fetch('branch_index') : branch_row.fetch('index')

    [
      pool_fs,
      dataset_full_name,
      "tree.#{tree_index}",
      "branch-#{branch_name}.#{branch_index}"
    ].join('/')
  end

  def create_remote_backup_vps_with_backups(services, primary_node:, backup_node:, admin_user_id:, primary_node_id:,
                                            backup_node_id:, hostname:, primary_pool_fs:, backup_pool_defs:)
    primary_pool = create_pool(
      services,
      node_id: primary_node_id,
      label: "#{hostname}-primary",
      filesystem: primary_pool_fs,
      role: 'hypervisor'
    )
    backup_pools = backup_pool_defs.each_with_object({}) do |pool_def, acc|
      label = pool_def.fetch(:label)

      acc[label] = create_pool(
        services,
        node_id: backup_node_id,
        label: "#{hostname}-#{label}",
        filesystem: pool_def.fetch(:filesystem),
        role: 'backup'
      )
    end

    wait_for_pool_online(services, primary_pool.fetch('id'))
    backup_pools.each_value do |pool|
      wait_for_pool_online(services, pool.fetch('id'))
    end

    vps = create_vps(
      services,
      admin_user_id: admin_user_id,
      node_id: primary_node_id,
      hostname: hostname
    )

    info = nil
    wait_until_block_succeeds(name: "dataset info available for VPS #{vps.fetch('id')}") do
      info = dataset_info(services, vps.fetch('id'))
      !info.nil?
    end

    backup_pool_ids = {}
    dst_dip_ids = {}
    backup_dataset_paths = {}

    backup_pool_defs.each do |pool_def|
      label = pool_def.fetch(:label)
      pool = backup_pools.fetch(label)

      backup_info = ensure_dataset_in_pool(
        services,
        admin_user_id: admin_user_id,
        dataset_id: info.fetch('dataset_id'),
        pool_id: pool.fetch('id')
      )

      backup_pool_ids[label] = pool.fetch('id')
      dst_dip_ids[label] = backup_info.fetch('dataset_in_pool_id')
      backup_dataset_paths[label] = "#{pool_def.fetch(:filesystem)}/#{info.fetch('dataset_full_name')}"
    end

    primary_dataset_path = "#{primary_pool_fs}/#{info.fetch('dataset_full_name')}"

    wait_until_block_succeeds(name: "primary dataset #{primary_dataset_path} exists") do
      primary_node.zfs_exists?(primary_dataset_path, type: 'filesystem', timeout: 30)
    end

    backup_dataset_paths.each do |label, dataset_path|
      wait_until_block_succeeds(name: "backup dataset #{label} #{dataset_path} exists") do
        backup_node.zfs_exists?(dataset_path, type: 'filesystem', timeout: 30)
      end
    end

    {
      'primary_pool_id' => primary_pool.fetch('id'),
      'backup_pool_ids' => backup_pool_ids,
      'vps_id' => vps.fetch('id'),
      'dataset_id' => info.fetch('dataset_id'),
      'src_dip_id' => info.fetch('dataset_in_pool_id'),
      'dst_dip_ids' => dst_dip_ids,
      'dataset_full_name' => info.fetch('dataset_full_name'),
      'primary_dataset_path' => primary_dataset_path,
      'backup_dataset_paths' => backup_dataset_paths
    }
  end

  def create_remote_backup_dataset_with_backups(services, primary_node:, backup_node:, admin_user_id:, primary_node_id:,
                                                backup_node_id:, dataset_name:, primary_pool_fs:, backup_pool_defs:,
                                                refquota: 10_240)
    primary_pool = create_pool(
      services,
      node_id: primary_node_id,
      label: "#{dataset_name}-primary",
      filesystem: primary_pool_fs,
      role: 'primary'
    )
    backup_pools = backup_pool_defs.each_with_object({}) do |pool_def, acc|
      label = pool_def.fetch(:label)

      acc[label] = create_pool(
        services,
        node_id: backup_node_id,
        label: "#{dataset_name}-#{label}",
        filesystem: pool_def.fetch(:filesystem),
        role: 'backup'
      )
    end

    wait_for_pool_online(services, primary_pool.fetch('id'))
    backup_pools.each_value do |pool|
      wait_for_pool_online(services, pool.fetch('id'))
    end

    info = services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      user = User.find(#{Integer(admin_user_id)})
      pool = Pool.find(#{Integer(primary_pool.fetch('id'))})
      dataset = Dataset.new(
        name: #{dataset_name.inspect},
        user: user,
        user_editable: true,
        user_create: true,
        user_destroy: true,
        confirmed: Dataset.confirmed(:confirm_create)
      )
      chain, created = TransactionChains::Dataset::Create.fire(
        pool,
        nil,
        [dataset],
        automount: false,
        properties: { refquota: #{Integer(refquota)} },
        user: user,
        label: #{dataset_name.inspect}
      )
      dip = Array(created).last

      puts JSON.dump(
        chain_id: chain.id,
        dataset_id: dataset.id,
        dataset_in_pool_id: dip.id,
        dataset_full_name: dataset.full_name
      )
    RUBY

    services.wait_for_chain_state(info.fetch('chain_id'), state: :done)

    backup_pool_ids = {}
    dst_dip_ids = {}
    backup_dataset_paths = {}

    backup_pool_defs.each do |pool_def|
      label = pool_def.fetch(:label)
      pool = backup_pools.fetch(label)

      backup_info = ensure_dataset_in_pool(
        services,
        admin_user_id: admin_user_id,
        dataset_id: info.fetch('dataset_id'),
        pool_id: pool.fetch('id')
      )

      backup_pool_ids[label] = pool.fetch('id')
      dst_dip_ids[label] = backup_info.fetch('dataset_in_pool_id')
      backup_dataset_paths[label] = "#{pool_def.fetch(:filesystem)}/#{info.fetch('dataset_full_name')}"
    end

    primary_dataset_path = "#{primary_pool_fs}/#{info.fetch('dataset_full_name')}"

    wait_until_block_succeeds(name: "primary dataset #{primary_dataset_path} exists") do
      primary_node.zfs_exists?(primary_dataset_path, type: 'filesystem', timeout: 30)
    end

    backup_dataset_paths.each do |label, dataset_path|
      wait_until_block_succeeds(name: "backup dataset #{label} #{dataset_path} exists") do
        backup_node.zfs_exists?(dataset_path, type: 'filesystem', timeout: 30)
      end
    end

    {
      'primary_pool_id' => primary_pool.fetch('id'),
      'backup_pool_ids' => backup_pool_ids,
      'dataset_id' => info.fetch('dataset_id'),
      'src_dip_id' => info.fetch('dataset_in_pool_id'),
      'dst_dip_ids' => dst_dip_ids,
      'dataset_full_name' => info.fetch('dataset_full_name'),
      'primary_dataset_path' => primary_dataset_path,
      'backup_dataset_paths' => backup_dataset_paths
    }
  end

  def create_remote_backup_dataset(services, primary_node:, backup_node:, admin_user_id:, primary_node_id:,
                                   backup_node_id:, dataset_name:, primary_pool_fs:, backup_pool_fs:)
    setup = create_remote_backup_dataset_with_backups(
      services,
      primary_node: primary_node,
      backup_node: backup_node,
      admin_user_id: admin_user_id,
      primary_node_id: primary_node_id,
      backup_node_id: backup_node_id,
      dataset_name: dataset_name,
      primary_pool_fs: primary_pool_fs,
      backup_pool_defs: [
        {
          label: 'backup',
          filesystem: backup_pool_fs
        }
      ]
    )

    {
      'primary_pool_id' => setup.fetch('primary_pool_id'),
      'backup_pool_id' => setup.fetch('backup_pool_ids').fetch('backup'),
      'dataset_id' => setup.fetch('dataset_id'),
      'src_dip_id' => setup.fetch('src_dip_id'),
      'dst_dip_id' => setup.fetch('dst_dip_ids').fetch('backup'),
      'dataset_full_name' => setup.fetch('dataset_full_name'),
      'primary_dataset_path' => setup.fetch('primary_dataset_path'),
      'backup_dataset_path' => setup.fetch('backup_dataset_paths').fetch('backup')
    }
  end

  def create_remote_backup_vps(services, primary_node:, backup_node:, admin_user_id:, primary_node_id:, backup_node_id:,
                               hostname:, primary_pool_fs:, backup_pool_fs:)
    setup = create_remote_backup_vps_with_backups(
      services,
      primary_node: primary_node,
      backup_node: backup_node,
      admin_user_id: admin_user_id,
      primary_node_id: primary_node_id,
      backup_node_id: backup_node_id,
      hostname: hostname,
      primary_pool_fs: primary_pool_fs,
      backup_pool_defs: [
        {
          label: 'backup',
          filesystem: backup_pool_fs
        }
      ]
    )

    {
      'primary_pool_id' => setup.fetch('primary_pool_id'),
      'backup_pool_id' => setup.fetch('backup_pool_ids').fetch('backup'),
      'vps_id' => setup.fetch('vps_id'),
      'dataset_id' => setup.fetch('dataset_id'),
      'src_dip_id' => setup.fetch('src_dip_id'),
      'dst_dip_id' => setup.fetch('dst_dip_ids').fetch('backup'),
      'dataset_full_name' => setup.fetch('dataset_full_name'),
      'primary_dataset_path' => setup.fetch('primary_dataset_path'),
      'backup_dataset_path' => setup.fetch('backup_dataset_paths').fetch('backup')
    }
  end

  configure_examples do |config|
    config.default_order = :defined
  end

  ${
    if manageCluster then
      ''
        before(:suite) do
          services.start
          node1.start
          node2.start
          services.wait_for_vpsadmin_api
          wait_for_running_nodectld(node1)
          wait_for_running_nodectld(node2)
          wait_for_node_ready(services, node1_id)
          wait_for_node_ready(services, node2_id)
          prepare_node_queues(node1)
          prepare_node_queues(node2)
          services.unlock_transaction_signing_key(passphrase: 'test')
        end
      ''
    else
      ""
  }
''
