{
  adminUserId,
  node1Id,
  node2Id ? node1Id,
  manageCluster ? false,
}:
let
  base = import ../storage/remote-common.nix {
    inherit
      adminUserId
      node1Id
      node2Id
      manageCluster
      ;
  };
in
base
+ ''
  def start_vps(services, vps_id)
    services.vpsadminctl.succeeds(args: ['vps', 'start', Integer(vps_id).to_s])
    wait_for_vps_running(services, vps_id)
    vps_id
  end

  def stop_vps(services, vps_id, node_id:)
    services.vpsadminctl.succeeds(args: ['vps', 'stop', Integer(vps_id).to_s])
    wait_for_vps_on_node(services, vps_id: vps_id, node_id: node_id, running: false)
    vps_id
  end

  def tx_types(services)
    @network_tx_types ||= services.api_ruby_json(code: <<~RUBY)
      puts JSON.dump({
        export_create: Transactions::Export::Create.t_type,
        export_destroy: Transactions::Export::Destroy.t_type,
        export_disable: Transactions::Export::Disable.t_type,
        export_del_hosts: Transactions::Export::DelHosts.t_type,
        export_add_hosts: Transactions::Export::AddHosts.t_type,
        export_enable: Transactions::Export::Enable.t_type,
        export_set: Transactions::Export::Set.t_type,
        netif_create_veth_routed: Transactions::NetworkInterface::CreateVethRouted.t_type,
        netif_remove_veth_routed: Transactions::Vps::RemoveVeth.t_type,
        netif_rename: Transactions::NetworkInterface::Rename.t_type,
        netif_enable: Transactions::NetworkInterface::Enable.t_type,
        netif_disable: Transactions::NetworkInterface::Disable.t_type,
        netif_set_shaper: Transactions::NetworkInterface::SetShaper.t_type,
        netif_add_route: Transactions::NetworkInterface::AddRoute.t_type,
        netif_del_route: Transactions::NetworkInterface::DelRoute.t_type,
        netif_add_host_ip: Transactions::NetworkInterface::AddHostIp.t_type,
        netif_del_host_ip: Transactions::NetworkInterface::DelHostIp.t_type
      })
    RUBY
  end

  def create_veth_routed_netif(services, admin_user_id:, vps_id:, name:)
    services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      vps = Vps.find(#{Integer(vps_id)})
      chain, netif = TransactionChains::NetworkInterface::VethRouted::Create.fire(vps, #{name.inspect})

      puts JSON.dump(chain_id: chain.id, netif_id: netif.id)
    RUBY
  end

  def update_netif(services, admin_user_id:, netif_id:, attrs:)
    services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      netif = NetworkInterface.find(#{Integer(netif_id)})
      chain, updated = TransactionChains::NetworkInterface::Update.fire(netif, #{attrs.inspect})

      puts JSON.dump(chain_id: chain.id, netif_id: updated.id)
    RUBY
  end

  def destroy_netif(services, admin_user_id:, netif_id:, clear: true)
    services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      netif = NetworkInterface.find(#{Integer(netif_id)})
      chain, = TransactionChains::NetworkInterface::Destroy.fire(
        netif,
        clear: #{clear ? 'true' : 'false'}
      )

      puts JSON.dump(chain_id: chain.id, netif_id: netif.id)
    RUBY
  end

  def create_private_vps_network_with_ips(services, admin_user_id:, vps_id:, count: 1)
    services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      vps = Vps.find(#{Integer(vps_id)})
      location = vps.node.location

      network = Network.find_or_initialize_by(address: '203.0.113.0', prefix: 24)
      network.assign_attributes(
        label: 'Network Test Net',
        ip_version: 4,
        role: :private_access,
        managed: true,
        split_access: :no_access,
        split_prefix: 32,
        purpose: :vps,
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
        addr = '203.0.113.' + (10 + i).to_s
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

        host_ip = ip.host_ip_addresses.first || HostIpAddress.create!(
          ip_address: ip,
          ip_addr: ip.ip_addr,
          order: nil
        )

        seeded_ips << {
          id: ip.id,
          addr: ip.ip_addr,
          host_ip_id: host_ip.id
        }
      end

      puts JSON.dump(
        network_id: network.id,
        location_id: location.id,
        environment_id: location.environment_id,
        ip_addresses: seeded_ips
      )
    RUBY
  end

  def add_route_to_netif(services, admin_user_id:, netif_id:, ip_id:)
    services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      netif = NetworkInterface.find(#{Integer(netif_id)})
      ip = IpAddress.find(#{Integer(ip_id)})
      chain, = TransactionChains::NetworkInterface::AddRoute.fire(netif, [ip])

      puts JSON.dump(chain_id: chain.id, ip_id: ip.id)
    RUBY
  end

  def del_route_from_netif(services, admin_user_id:, netif_id:, ip_id:)
    services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      netif = NetworkInterface.find(#{Integer(netif_id)})
      ip = IpAddress.find(#{Integer(ip_id)})
      chain, = TransactionChains::NetworkInterface::DelRoute.fire(netif, [ip])

      puts JSON.dump(chain_id: chain.id, ip_id: ip.id)
    RUBY
  end

  def add_host_ip_to_netif(services, admin_user_id:, netif_id:, host_ip_id:)
    services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      netif = NetworkInterface.find(#{Integer(netif_id)})
      addr = HostIpAddress.find(#{Integer(host_ip_id)})
      chain, = TransactionChains::NetworkInterface::AddHostIp.fire(netif, [addr])

      puts JSON.dump(chain_id: chain.id, host_ip_id: addr.id)
    RUBY
  end

  def del_host_ip_from_netif(services, admin_user_id:, netif_id:, host_ip_id:)
    services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      netif = NetworkInterface.find(#{Integer(netif_id)})
      addr = HostIpAddress.find(#{Integer(host_ip_id)})
      chain, = TransactionChains::NetworkInterface::DelHostIp.fire(netif, [addr])

      puts JSON.dump(chain_id: chain.id, host_ip_id: addr.id)
    RUBY
  end

  def network_interface_row(services, netif_id)
    row = services.mysql_json_rows(sql: <<~SQL).first
      SELECT JSON_OBJECT(
        'id', n.id,
        'vps_id', n.vps_id,
        'export_id', n.export_id,
        'name', n.name,
        'enable', n.enable,
        'max_tx', n.max_tx,
        'max_rx', n.max_rx
      )
      FROM network_interfaces n
      WHERE n.id = #{Integer(netif_id)}
      LIMIT 1
    SQL

    return nil if row.nil?

    row.merge(
      'enable' => row.fetch('enable') == true || row.fetch('enable').to_i == 1
    )
  end

  def ip_address_row(services, ip_id)
    services.mysql_json_rows(sql: <<~SQL).first
      SELECT JSON_OBJECT(
        'id', ip.id,
        'addr', ip.ip_addr,
        'prefix', ip.prefix,
        'network_interface_id', ip.network_interface_id,
        'route_via_id', ip.route_via_id,
        'charged_environment_id', ip.charged_environment_id,
        'order', ip.`order`
      )
      FROM ip_addresses ip
      WHERE ip.id = #{Integer(ip_id)}
      LIMIT 1
    SQL
  end

  def host_ip_address_row(services, host_ip_id)
    services.mysql_json_rows(sql: <<~SQL).first
      SELECT JSON_OBJECT(
        'id', h.id,
        'ip_address_id', h.ip_address_id,
        'addr', h.ip_addr,
        'order', h.`order`
      )
      FROM host_ip_addresses h
      WHERE h.id = #{Integer(host_ip_id)}
      LIMIT 1
    SQL
  end

  def environment_user_resource_uses(services, user_id:, environment_id:)
    services.mysql_json_rows(sql: <<~SQL)
      SELECT JSON_OBJECT(
        'resource', cr.name,
        'value', cru.value,
        'class_name', cru.class_name,
        'row_id', cru.row_id
      )
      FROM cluster_resource_uses cru
      INNER JOIN user_cluster_resources ucr ON ucr.id = cru.user_cluster_resource_id
      INNER JOIN cluster_resources cr ON cr.id = ucr.cluster_resource_id
      WHERE ucr.user_id = #{Integer(user_id)}
        AND ucr.environment_id = #{Integer(environment_id)}
        AND cru.class_name = 'EnvironmentUserConfig'
      ORDER BY cr.name
    SQL
  end

  def export_runtime_row(services, export_id)
    row = services.mysql_json_rows(sql: <<~SQL).first
      SELECT JSON_OBJECT(
        'id', e.id,
        'path', e.path,
        'enabled', e.enabled,
        'network_interface_id', n.id,
        'ip_address_id', ip.id,
        'host_ip_id', h.id
      )
      FROM exports e
      LEFT JOIN network_interfaces n ON n.export_id = e.id
      LEFT JOIN ip_addresses ip ON ip.network_interface_id = n.id
      LEFT JOIN host_ip_addresses h ON h.ip_address_id = ip.id
      WHERE e.id = #{Integer(export_id)}
      ORDER BY h.id
      LIMIT 1
    SQL

    return nil if row.nil?

    row.merge(
      'enabled' => row.fetch('enabled') == true || row.fetch('enabled').to_i == 1
    )
  end

  def export_host_rows(services, export_id)
    services.mysql_json_rows(sql: <<~SQL)
      SELECT JSON_OBJECT(
        'id', h.id,
        'export_id', h.export_id,
        'ip_address_id', h.ip_address_id,
        'addr', ip.ip_addr
      )
      FROM export_hosts h
      INNER JOIN ip_addresses ip ON ip.id = h.ip_address_id
      WHERE h.export_id = #{Integer(export_id)}
      ORDER BY h.id
    SQL
  end

  def update_export(services, admin_user_id:, export_id:, attrs:)
    services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      export = Export.find(#{Integer(export_id)})
      chain, updated = VpsAdmin::API::Operations::Export::Update.run(export, #{attrs.inspect})

      puts JSON.dump(chain_id: chain.id, export_id: updated.id)
    RUBY
  end

  def destroy_export(services, admin_user_id:, export_id:)
    services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      export = Export.find(#{Integer(export_id)})
      chain = VpsAdmin::API::Operations::Export::Destroy.run(export)

      puts JSON.dump(chain_id: chain.id, export_id: #{Integer(export_id)})
    RUBY
  end

  def del_export_host(services, admin_user_id:, export_id:, export_host_id:)
    services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      export = Export.find(#{Integer(export_id)})
      host = ExportHost.find(#{Integer(export_host_id)})
      chain = VpsAdmin::API::Operations::Export::DelHost.run(export, host)

      puts JSON.dump(chain_id: chain.id, export_host_id: host.id)
    RUBY
  end

  def export_runtime_dump(node, export_id)
    _, output = node.succeeds(
      "osctl-exportfs export ls #{Integer(export_id)} || true",
      timeout: 60
    )
    output
  end

  def export_server_runtime_dump(node)
    _, output = node.succeeds(
      'osctl-exportfs server ls -H -o server,state,address || true',
      timeout: 60
    )
    output
  end

  def export_server_running?(node, export_id)
    export_server_runtime_dump(node).to_s.each_line.any? do |line|
      cols = line.strip.split(/\s+/)
      cols[0] == Integer(export_id).to_s && cols[1] == 'running'
    end
  end

  def wait_for_export_present(node, export_id, expected_path:)
    wait_until_block_succeeds(name: "export #{export_id} present on #{node.name}") do
      export_server_running?(node, export_id)
    end
  end

  def wait_for_export_absent(node, export_id, expected_path:)
    wait_until_block_succeeds(name: "export #{export_id} absent on #{node.name}") do
      !export_server_runtime_dump(node).to_s.each_line.any? do |line|
        line.strip.split(/\s+/).first == Integer(export_id).to_s
      end
    end
  end

  def runtime_netif_names(node, vps_id)
    _, output = node.succeeds(
      "osctl -j ct netif ls #{Integer(vps_id)}",
      timeout: 60
    )

    JSON.parse(output.to_s).map do |row|
      row.fetch('name')
    end
  end

  def wait_for_netif_present(node, vps_id:, name:)
    wait_until_block_succeeds(name: "netif #{name} present on #{node.name}") do
      runtime_netif_names(node, vps_id).include?(name)
    end
  end

  def wait_for_netif_absent(node, vps_id:, name:)
    wait_until_block_succeeds(name: "netif #{name} absent on #{node.name}") do
      !runtime_netif_names(node, vps_id).include?(name)
    end
  end

  def route_runtime_dump(node, vps_id:, name:)
    _, output = node.succeeds(
      "osctl ct netif route ls #{Integer(vps_id)} #{Shellwords.escape(name)} || true",
      timeout: 60
    )
    output
  end

  def runtime_listing_includes_addr?(output, cidr)
    addr = cidr.to_s.split('/').first

    output.to_s.each_line.any? do |line|
      cols = line.strip.split(/\s+/)
      cols.any? { |col| col.split('/').first == addr }
    end
  end

  def wait_for_route_present(node, vps_id:, name:, cidr:)
    wait_until_block_succeeds(name: "route #{cidr} present on #{node.name}:#{name}") do
      runtime_listing_includes_addr?(
        route_runtime_dump(node, vps_id: vps_id, name: name),
        cidr
      )
    end
  end

  def wait_for_route_absent(node, vps_id:, name:, cidr:)
    wait_until_block_succeeds(name: "route #{cidr} absent on #{node.name}:#{name}") do
      !runtime_listing_includes_addr?(
        route_runtime_dump(node, vps_id: vps_id, name: name),
        cidr
      )
    end
  end

  def host_ip_runtime_dump(node, vps_id:, name:)
    _, output = node.succeeds(
      "osctl ct netif ip ls #{Integer(vps_id)} #{Shellwords.escape(name)} || true",
      timeout: 60
    )
    output
  end

  def wait_for_host_ip_present(node, vps_id:, name:, cidr:)
    wait_until_block_succeeds(name: "host ip #{cidr} present on #{node.name}:#{name}") do
      runtime_listing_includes_addr?(
        host_ip_runtime_dump(node, vps_id: vps_id, name: name),
        cidr
      )
    end
  end

  def wait_for_host_ip_absent(node, vps_id:, name:, cidr:)
    wait_until_block_succeeds(name: "host ip #{cidr} absent on #{node.name}:#{name}") do
      !runtime_listing_includes_addr?(
        host_ip_runtime_dump(node, vps_id: vps_id, name: name),
        cidr
      )
    end
  end
''
