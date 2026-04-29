{
  adminUserId,
  node1Id,
  nodeDomain,
  rabbitmqVhost,
  rabbitSupervisorUser,
}:
let
  base = import ../storage/remote-common.nix {
    inherit adminUserId node1Id;
    node2Id = node1Id;
    manageCluster = false;
  };
in
base
+ ''
  require 'securerandom'

  def rabbitmq_vhost
    ${builtins.toJSON rabbitmqVhost}
  end

  def rabbitmq_supervisor_user
    ${builtins.toJSON rabbitSupervisorUser.user}
  end

  def rabbitmq_supervisor_password
    ${builtins.toJSON rabbitSupervisorUser.password}
  end

  def supervisor_exchange_name
    "node:${nodeDomain}"
  end

  def setup_supervisor_cluster(services, node, pool_label: 'supervisor-hv')
    [services, node].each(&:start)
    services.wait_for_vpsadmin_api
    services.wait_for_service('vpsadmin-rabbitmq-setup.service')
    services.wait_for_service('vpsadmin-supervisor.service')
    wait_for_supervisor_node_process(node)
    ensure_supervisor_mail_templates(services)
  end

  def wait_for_supervisor_node_process(node)
    node.wait_for_service('nodectld')
    wait_until_block_succeeds(name: "nodectld process on #{node.name}") do
      _, output = node.succeeds('sv check nodectld', timeout: 30)
      expect(output).to include('ok: run: nodectld')
      true
    end
  end

  def publish_supervisor_payload(services, routing_key:, payload:)
    json = JSON.dump(payload)

    services.api_ruby_json(code: <<~RUBY)
      require 'bunny'

      conn = Bunny.new(
        hostname: '127.0.0.1',
        vhost: #{rabbitmq_vhost.inspect},
        username: #{rabbitmq_supervisor_user.inspect},
        password: #{rabbitmq_supervisor_password.inspect}
      )
      conn.start
      ch = conn.create_channel
      ex = ch.direct(#{supervisor_exchange_name.inspect})
      ex.publish(
        #{json.inspect},
        routing_key: #{routing_key.inspect},
        content_type: 'application/json'
      )
      conn.close

      puts JSON.dump(ok: true)
    RUBY
  end

  def create_supervisor_vps(services, hostname:, start: false, diskspace: 10_240)
    services.api_ruby_json(code: <<~RUBY)
      admin = User.find(#{admin_user_id})
      node = Node.find(#{node1_id})
      env = node.location.environment
      User.current = admin
      UserSession.current = UserSession.create!(
        user: admin,
        auth_type: 'basic',
        api_ip_addr: '127.0.0.1',
        client_version: 'supervisor-integration'
      )

      ClusterResource.find_each do |resource|
        record = UserClusterResource.find_or_initialize_by(
          user: admin,
          environment: env,
          cluster_resource: resource
        )
        record.value = [record.value.to_i, 1_000_000].max
        record.save! if record.changed?
      end

      pool = Pool.find_or_initialize_by(filesystem: #{primary_pool_fs.inspect})
      pool.assign_attributes(
        node: node,
        label: 'Supervisor integration pool',
        role: :hypervisor,
        is_open: true,
        max_datasets: 100,
        refquota_check: true
      )
      pool.save! if pool.changed? || pool.new_record?

      VpsAdmin::API::DatasetProperties::Registrator.properties.each do |name, prop|
        DatasetProperty.find_or_create_by!(
          pool: pool,
          dataset_in_pool_id: nil,
          dataset_id: nil,
          name: name.to_s
        ) do |p|
          p.value = prop.meta[:default]
          p.inherited = false
          p.confirmed = DatasetProperty.confirmed(:confirmed)
        end
      end

      dataset = Dataset.create!(
        user: admin,
        name: #{hostname.inspect} + '-' + SecureRandom.hex(4),
        user_editable: true,
        user_create: true,
        user_destroy: true,
        confirmed: Dataset.confirmed(:confirmed)
      )
      dip = DatasetInPool.create!(
        dataset: dataset,
        pool: pool,
        confirmed: DatasetInPool.confirmed(:confirmed)
      )
      DatasetProperty.inherit_properties!(dip, {}, { refquota: #{Integer(diskspace)} })
      dip.allocate_resource!(
        :diskspace,
        #{Integer(diskspace)},
        user: admin,
        confirmed: ClusterResourceUse.confirmed(:confirmed),
        admin_override: true
      )

      offset = (UserNamespace.maximum(:offset) || 131_072) + 65_536
      userns = UserNamespace.create!(
        user: admin,
        block_count: 1,
        offset: offset,
        size: 65_536
      )
      userns_map = UserNamespaceMap.create!(
        user_namespace: userns,
        label: 'supervisor-' + SecureRandom.hex(4)
      )

      vps = Vps.create!(
        user: admin,
        node: node,
        hostname: #{hostname.inspect},
        os_template: OsTemplate.first,
        dns_resolver: DnsResolver.first,
        dataset_in_pool: dip,
        user_namespace_map: userns_map,
        object_state: :active,
        confirmed: Vps.confirmed(:confirmed)
      )
      vps.allocate_resources(
        required: %i[cpu memory swap],
        optional: [],
        user: admin,
        confirmed: ClusterResourceUse.confirmed(:confirmed),
        values: { cpu: 1, memory: 1024, swap: 0 },
        admin_override: true
      )

      puts JSON.dump(id: vps.id, hostname: vps.hostname)
    RUBY
  end

  def ensure_vps_current_status(services, vps_id)
    services.api_ruby_json(code: <<~RUBY)
      vps = Vps.find(#{Integer(vps_id)})
      status = VpsCurrentStatus.find_or_initialize_by(vps: vps)
      status.status = false if status.status.nil?
      status.is_running = false if status.is_running.nil?
      status.update_count ||= 1
      status.save! if status.changed? || status.new_record?

      puts JSON.dump(id: status.id, vps_id: vps.id)
    RUBY
  end

  def supervisor_vps_info(services, vps_id)
    services.api_ruby_json(code: <<~RUBY)
      vps = Vps.find(#{Integer(vps_id)})
      dip = vps.dataset_in_pool
      props = dip.dataset_properties.where(
        name: %w[refquota referenced used available compressratio]
      ).each_with_object({}) do |prop, ret|
        ret[prop.name] = {
          id: prop.id,
          value: prop.value
        }
      end

      puts JSON.dump(
        vps_id: vps.id,
        user_id: vps.user_id,
        dataset_id: dip.dataset_id,
        dataset_in_pool_id: dip.id,
        pool_id: dip.pool_id,
        properties: props
      )
    RUBY
  end

  def ensure_supervisor_netif(services, vps_id:, name: 'eth-supervisor')
    services.api_ruby_json(code: <<~RUBY)
      vps = Vps.find(#{Integer(vps_id)})
      netif = NetworkInterface.find_or_create_by!(vps: vps, name: #{name.inspect}) do |n|
        n.kind = :veth_routed
        n.max_tx = 0
        n.max_rx = 0
      end

      puts JSON.dump(id: netif.id, vps_id: vps.id, user_id: vps.user_id)
    RUBY
  end

  def seed_export_mount(services, vps_id:, export_id:, mountpoint:, nfs_version:)
    services.api_ruby_json(code: <<~RUBY)
      mount = ExportMount.create!(
        vps: Vps.find(#{Integer(vps_id)}),
        export: Export.find(#{Integer(export_id)}),
        mountpoint: #{mountpoint.inspect},
        nfs_version: #{nfs_version.inspect}
      )

      puts JSON.dump(id: mount.id)
    RUBY
  end

  def seed_supervisor_export(services, dataset_id:, ip_address_id:)
    services.api_ruby_json(code: <<~RUBY)
      dataset = Dataset.find(#{Integer(dataset_id)})
      dip = dataset.primary_dataset_in_pool!
      ip = IpAddress.find(#{Integer(ip_address_id)})
      export = nil

      Uuid.generate_for_new_record! do |uuid|
        export = Export.new(
          dataset_in_pool: dip,
          snapshot_in_pool_clone: nil,
          snapshot_in_pool_clone_n: 0,
          user: dataset.user,
          all_vps: false,
          path: '/export/' + dataset.full_name,
          rw: true,
          sync: true,
          subtree_check: false,
          root_squash: false,
          threads: 8,
          enabled: true,
          object_state: :active,
          confirmed: Export.confirmed(:confirmed)
        )
        export.uuid = uuid
        export.save!
        export
      end

      netif = NetworkInterface.create!(
        export: export,
        kind: :veth_routed,
        name: 'supervisor-export'
      )
      ip.update!(network_interface: netif)

      HostIpAddress.find_or_create_by!(ip_address: ip, ip_addr: ip.ip_addr)
      ExportHost.find_or_create_by!(export: export, ip_address: ip) do |host|
        host.rw = true
        host.sync = true
        host.subtree_check = false
        host.root_squash = false
      end

      puts JSON.dump(id: export.id, path: export.path)
    RUBY
  end

  def seed_vps_mount(services, vps_id:, mountpoint:)
    services.api_ruby_json(code: <<~RUBY)
      vps = Vps.find(#{Integer(vps_id)})
      pool = vps.dataset_in_pool.pool
      dataset = Dataset.create!(
        user: vps.user,
        parent: vps.dataset,
        name: 'supervisor-mount-' + SecureRandom.hex(4),
        user_editable: true,
        user_create: true,
        user_destroy: true,
        confirmed: Dataset.confirmed(:confirmed)
      )
      dip = DatasetInPool.create!(
        dataset: dataset,
        pool: pool,
        confirmed: DatasetInPool.confirmed(:confirmed)
      )
      DatasetProperty.inherit_properties!(dip, {}, { refquota: 1024 })
      mount = Mount.create!(
        vps: vps,
        dataset_in_pool: dip,
        dst: #{mountpoint.inspect},
        mount_opts: '--bind',
        umount_opts: '-f',
        mount_type: 'bind',
        user_editable: false,
        mode: 'rw',
        enabled: true,
        master_enabled: true,
        on_start_fail: :mount_later,
        object_state: :active,
        confirmed: Mount.confirmed(:confirmed)
      )

      puts JSON.dump(id: mount.id, dataset_id: dataset.id, dataset_in_pool_id: dip.id)
    RUBY
  end

  def ensure_supervisor_mail_templates(services)
    services.api_ruby_json(code: <<~RUBY)
      %w[vps_dataset_expanded vps_incident_report].each do |name|
        template = MailTemplate.find_or_create_by!(name: name) do |tpl|
          tpl.label = name.tr('_', ' ').capitalize
          tpl.template_id = name
        end

        next if template.mail_template_translations.where(language: Language.first).exists?

        template.mail_template_translations.create!(
          language: Language.first,
          from: 'noreply@test.invalid',
          subject: name + ' subject',
          text_plain: name + ' body'
        )
      end

      puts JSON.dump(ok: true)
    RUBY
  end

  def wait_for_row(name, timeout: 60)
    row = nil

    wait_until_block_succeeds(name: name, timeout: timeout) do
      row = yield
      !row.nil?
    end

    row
  end

  def node_current_status_row(services, node_id:)
    services.mysql_json_rows(sql: <<~SQL).first
      SELECT JSON_OBJECT(
        'node_id', node_id,
        'uptime', uptime,
        'process_count', process_count,
        'loadavg1', loadavg1,
        'total_memory', total_memory,
        'used_memory', used_memory,
        'total_swap', total_swap,
        'used_swap', used_swap,
        'arc_size', arc_size,
        'pool_state', pool_state,
        'pool_scan', pool_scan
      )
      FROM node_current_statuses
      WHERE node_id = #{Integer(node_id)}
      LIMIT 1
    SQL
  end

  def vps_current_status_row(services, vps_id:)
    services.mysql_json_rows(sql: <<~SQL).first
      SELECT JSON_OBJECT(
        'vps_id', vps_id,
        'status', status,
        'is_running', is_running,
        'halted', halted,
        'uptime', uptime,
        'process_count', process_count,
        'used_memory', used_memory,
        'total_diskspace', total_diskspace,
        'used_diskspace', used_diskspace,
        'cpu_idle', cpu_idle
      )
      FROM vps_current_statuses
      WHERE vps_id = #{Integer(vps_id)}
      LIMIT 1
    SQL
  end

  def dataset_property_row(services, property_id:)
    services.api_ruby_json(code: <<~RUBY)
      prop = DatasetProperty.find(#{Integer(property_id)})
      puts JSON.dump(
        id: prop.id,
        name: prop.name,
        value: prop.value,
        updated_at: prop.updated_at&.to_i
      )
    RUBY
  end

  def dataset_property_history_rows(services, property_id:)
    services.mysql_json_rows(sql: <<~SQL)
      SELECT JSON_OBJECT('id', id, 'value', value, 'created_at', UNIX_TIMESTAMP(created_at))
      FROM dataset_property_histories
      WHERE dataset_property_id = #{Integer(property_id)}
      ORDER BY id
    SQL
  end

  def dataset_expansion_history_rows(services, dataset_id:)
    services.mysql_json_rows(sql: <<~SQL)
      SELECT JSON_OBJECT(
        'id', h.id,
        'dataset_expansion_id', h.dataset_expansion_id,
        'original_refquota', h.original_refquota,
        'new_refquota', h.new_refquota,
        'added_space', h.added_space
      )
      FROM dataset_expansion_histories h
      INNER JOIN dataset_expansions e ON e.id = h.dataset_expansion_id
      WHERE e.dataset_id = #{Integer(dataset_id)}
      ORDER BY h.id
    SQL
  end

  def net_monitor_row(services, netif_id:)
    services.mysql_json_rows(sql: <<~SQL).first
      SELECT JSON_OBJECT(
        'network_interface_id', network_interface_id,
        'bytes', bytes,
        'bytes_in', bytes_in,
        'bytes_out', bytes_out,
        'packets', packets,
        'packets_in', packets_in,
        'packets_out', packets_out,
        'delta', delta
      )
      FROM network_interface_monitors
      WHERE network_interface_id = #{Integer(netif_id)}
      LIMIT 1
    SQL
  end

  def accounting_row(services, table:, netif_id:, user_id:, year:, month: nil, day: nil)
    conditions = [
      "network_interface_id = #{Integer(netif_id)}",
      "user_id = #{Integer(user_id)}",
      "year = #{Integer(year)}"
    ]
    conditions << "month = #{Integer(month)}" unless month.nil?
    conditions << "day = #{Integer(day)}" unless day.nil?

    services.mysql_json_rows(sql: <<~SQL).first
      SELECT JSON_OBJECT(
        'bytes_in', bytes_in,
        'bytes_out', bytes_out,
        'packets_in', packets_in,
        'packets_out', packets_out
      )
      FROM #{table}
      WHERE #{conditions.join(' AND ')}
      LIMIT 1
    SQL
  end

  def export_mount_rows(services, vps_id:)
    services.mysql_json_rows(sql: <<~SQL)
      SELECT JSON_OBJECT(
        'id', id,
        'export_id', export_id,
        'mountpoint', mountpoint,
        'nfs_version', nfs_version
      )
      FROM export_mounts
      WHERE vps_id = #{Integer(vps_id)}
      ORDER BY id
    SQL
  end

  def vps_mount_row(services, mount_id:)
    services.mysql_json_rows(sql: <<~SQL).first
      SELECT JSON_OBJECT('id', id, 'current_state', current_state)
      FROM mounts
      WHERE id = #{Integer(mount_id)}
      LIMIT 1
    SQL
  end

  def object_history_count(services, object_type:, object_id:, event_type:)
    services.mysql_json_rows(sql: <<~SQL).first.fetch('count').to_i
      SELECT JSON_OBJECT('count', COUNT(*))
      FROM object_histories
      WHERE tracked_object_type = #{object_type.inspect}
        AND tracked_object_id = #{Integer(object_id)}
        AND event_type = #{event_type.inspect}
    SQL
  end

  def incident_reports_for_vps(services, vps_id:)
    services.mysql_json_rows(sql: <<~SQL)
      SELECT JSON_OBJECT(
        'id', id,
        'codename', codename,
        'subject', subject,
        'text', text
      )
      FROM incident_reports
      WHERE vps_id = #{Integer(vps_id)}
      ORDER BY id
    SQL
  end
''
