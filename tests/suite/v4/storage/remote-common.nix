{
  adminUserId,
  node1Id,
  node2Id,
  primaryPoolFs ? "tank/ct",
  backupPoolFs ? "tank/backup",
}:
''
  require 'json'

  admin_user_id = ${toString adminUserId}
  node1_id = ${toString node1Id}
  node2_id = ${toString node2Id}
  primary_pool_fs = '${primaryPoolFs}'
  backup_pool_fs = '${backupPoolFs}'

  def wait_for_running_nodectld(node)
    node.wait_for_service('nodectld')
    wait_until_block_succeeds(name: "nodectld running on #{node.name}") do
      _, output = node.succeeds('nodectl status', timeout: 180)
      expect(output).to include('State: running')
      true
    end
  end

  def prepare_node_queues(node)
    node.succeeds('nodectl set config vpsadmin.queues.zfs_send.start_delay=0')
    node.succeeds('nodectl set config vpsadmin.queues.zfs_recv.start_delay=0')
    node.succeeds('nodectl queue resume all')
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
        recv: Transactions::Storage::Recv.t_type,
        send: Transactions::Storage::Send.t_type,
        recv_check: Transactions::Storage::RecvCheck.t_type,
        local_send: Transactions::Storage::LocalSend.t_type,
        prepare_rollback: Transactions::Storage::PrepareRollback.t_type,
        apply_rollback: Transactions::Storage::ApplyRollback.t_type,
        branch_dataset: Transactions::Storage::BranchDataset.t_type
      )
    RUBY
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
        'dataset_full_name', d.full_name
      )
      FROM vpses v
      INNER JOIN dataset_in_pools dip ON dip.id = v.dataset_in_pool_id
      INNER JOIN datasets d ON d.id = dip.dataset_id
      WHERE v.id = #{Integer(vps_id)}
    SQL
  end

  def snapshot_rows_for_dip(services, dip_id)
    services.mysql_json_rows(sql: <<~SQL)
      SELECT JSON_OBJECT('id', s.id, 'name', s.name, 'history_id', s.history_id)
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

  def dataset_in_pool_info(services, dataset_id:, pool_id:)
    services.mysql_json_rows(sql: <<~SQL).first
      SELECT JSON_OBJECT('dataset_in_pool_id', dip.id)
      FROM dataset_in_pools dip
      WHERE dip.dataset_id = #{Integer(dataset_id)} AND dip.pool_id = #{Integer(pool_id)}
      LIMIT 1
    SQL
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

  def fire_backup(services, admin_user_id:, src_dip_id:, dst_dip_id:)
    response = services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      src = DatasetInPool.find(#{src_dip_id})
      dst = DatasetInPool.find(#{dst_dip_id})
      chain, = TransactionChains::Dataset::Backup.fire(src, dst)

      puts JSON.dump(chain_id: chain.id)
    RUBY

    services.wait_for_chain_state(response.fetch('chain_id'), state: :done)
    response
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

  def build_repeated_rollback_topology(services, admin_user_id:, dataset_id:, src_dip_id:, dst_dip_id:, vps_id:,
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
    wait_for_vps_running(services, vps_id)

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
    wait_for_vps_running(services, vps_id)

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

  def rollback_dataset_to_snapshot(services, dataset_id:, snapshot_id:)
    _, output = services.vpsadminctl.succeeds(
      args: ['dataset.snapshot', 'rollback', dataset_id.to_s, snapshot_id.to_s]
    )

    {
      'chain_id' => output.dig('_meta', 'action_state_id') || output.dig('response', '_meta', 'action_state_id'),
      'output' => output
    }
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

  def destroy_backup_dataset(services, admin_user_id:, dip_id:)
    services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      dip = DatasetInPool.find(#{dip_id})
      chain, = TransactionChains::DatasetInPool::Destroy.fire(dip, recursive: true)

      puts JSON.dump(chain_id: chain.id)
    RUBY
  end

  def wait_for_vps_running(services, vps_id)
    wait_until_block_succeeds(name: "VPS #{vps_id} running") do
      _, output = services.vpsadminctl.succeeds(args: ['vps', 'show', vps_id.to_s])
      output.fetch('vps').fetch('is_running')
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

  def create_remote_backup_vps(services, primary_node:, backup_node:, admin_user_id:, primary_node_id:, backup_node_id:,
                               hostname:, primary_pool_fs:, backup_pool_fs:)
    primary_pool = create_pool(
      services,
      node_id: primary_node_id,
      label: "#{hostname}-primary",
      filesystem: primary_pool_fs,
      role: 'hypervisor'
    )
    backup_pool = create_pool(
      services,
      node_id: backup_node_id,
      label: "#{hostname}-backup",
      filesystem: backup_pool_fs,
      role: 'backup'
    )
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

    services.wait_for_dataset_in_pool(
      dataset_id: info.fetch('dataset_id'),
      pool_id: backup_pool.fetch('id')
    )

    backup_info = dataset_in_pool_info(
      services,
      dataset_id: info.fetch('dataset_id'),
      pool_id: backup_pool.fetch('id')
    )

    primary_dataset_path = "#{primary_pool_fs}/#{info.fetch('dataset_full_name')}"
    backup_dataset_path = "#{backup_pool_fs}/#{info.fetch('dataset_full_name')}"

    wait_until_block_succeeds(name: "primary dataset #{primary_dataset_path} exists") do
      primary_node.zfs_exists?(primary_dataset_path, type: 'filesystem', timeout: 30)
    end

    wait_until_block_succeeds(name: "backup dataset #{backup_dataset_path} exists") do
      backup_node.zfs_exists?(backup_dataset_path, type: 'filesystem', timeout: 30)
    end

    {
      'primary_pool_id' => primary_pool.fetch('id'),
      'backup_pool_id' => backup_pool.fetch('id'),
      'vps_id' => vps.fetch('id'),
      'dataset_id' => info.fetch('dataset_id'),
      'src_dip_id' => info.fetch('dataset_in_pool_id'),
      'dst_dip_id' => backup_info.fetch('dataset_in_pool_id'),
      'dataset_full_name' => info.fetch('dataset_full_name'),
      'primary_dataset_path' => primary_dataset_path,
      'backup_dataset_path' => backup_dataset_path
    }
  end

  configure_examples do |config|
    config.default_order = :defined
  end

  before(:suite) do
    [services, node1, node2].each(&:start)
    services.wait_for_vpsadmin_api
    wait_for_running_nodectld(node1)
    wait_for_running_nodectld(node2)
    prepare_node_queues(node1)
    prepare_node_queues(node2)
    services.unlock_transaction_signing_key(passphrase: 'test')
    @tx_types = storage_tx_types(services)
  end
''
