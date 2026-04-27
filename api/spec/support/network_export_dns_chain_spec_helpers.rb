# frozen_string_literal: true

require 'securerandom'

module NetworkExportDnsChainSpecHelpers
  def create_netif_vps_fixture!(
    user: SpecSeed.user,
    node: SpecSeed.node,
    dataset_name: "netif-#{SecureRandom.hex(4)}",
    netif_name: 'eth0',
    kind: :veth_routed,
    enable: true,
    max_tx: 0,
    max_rx: 0
  )
    pool = create_pool!(node: node, role: :primary)
    ensure_available_node_status!(pool.node)
    dataset, dip = create_dataset_with_pool!(user: user, pool: pool, name: dataset_name)
    vps = create_vps_for_dataset!(user: user, node: pool.node, dataset_in_pool: dip)
    netif = create_network_interface!(
      vps,
      name: netif_name,
      kind: kind,
      max_tx: max_tx,
      max_rx: max_rx
    )

    {
      pool: pool,
      dataset: dataset,
      dataset_in_pool: dip,
      vps: vps,
      netif: netif.tap { |n| n.update!(enable: enable) unless n.enable == enable }
    }
  end

  def create_private_network!(
    location: SpecSeed.location,
    address: nil,
    prefix: 24,
    split_prefix: 32,
    role: :private_access,
    purpose: :export,
    autopick: true,
    userpick: true
  )
    network_id = Network.maximum(:id).to_i + 10
    address ||= "10.#{(network_id / 256) % 256}.#{network_id % 256}.0"

    network = Network.create!(
      label: "Spec private #{SecureRandom.hex(3)}",
      address: address,
      prefix: prefix,
      ip_version: 4,
      role: role,
      managed: true,
      split_access: :no_access,
      split_prefix: split_prefix,
      purpose: purpose,
      primary_location: location
    )

    LocationNetwork.create!(
      location: location,
      network: network,
      primary: true,
      priority: 10,
      autopick: autopick,
      userpick: userpick
    )

    network
  end

  def create_dns_server!(
    node:,
    name: "spec-dns-#{SecureRandom.hex(4)}",
    hidden: false,
    enable_user_dns_zones: true,
    user_dns_zone_type: :primary_type,
    ipv4_addr: nil
  )
    DnsServer.create!(
      node: node,
      name: name,
      ipv4_addr: ipv4_addr || "192.0.2.#{DnsServer.maximum(:id).to_i + 50}",
      hidden: hidden,
      enable_user_dns_zones: enable_user_dns_zones,
      user_dns_zone_type: user_dns_zone_type
    )
  end

  def create_dns_zone!(
    name: "spec-#{SecureRandom.hex(4)}.example.test.",
    user: nil,
    source: :internal_source,
    role: :forward_role,
    enabled: true,
    email: nil
  )
    DnsZone.create!(
      name: name,
      user: user,
      zone_role: role,
      zone_source: source,
      enabled: enabled,
      label: '',
      default_ttl: 3600,
      email: email || (source.to_sym == :internal_source ? 'dns@example.test' : nil),
      reverse_network_address: nil,
      reverse_network_prefix: nil
    )
  end

  def create_dns_server_zone!(
    dns_zone:,
    dns_server:,
    zone_type: :primary_type,
    confirmed: :confirmed
  )
    DnsServerZone.create!(
      dns_zone: dns_zone,
      dns_server: dns_server,
      zone_type: zone_type,
      confirmed: DnsServerZone.confirmed(confirmed)
    )
  end

  def create_dns_record!(
    dns_zone:,
    name: '@',
    record_type: 'A',
    content: '192.0.2.20',
    ttl: nil,
    priority: nil,
    enabled: true,
    update_token: nil
  )
    DnsRecord.create!(
      dns_zone: dns_zone,
      name: name,
      record_type: record_type,
      content: content,
      ttl: ttl,
      priority: priority,
      enabled: enabled,
      update_token: update_token
    )
  end

  def create_dns_tsig_key!(
    name: "spec-key-#{SecureRandom.hex(4)}.",
    algorithm: 'hmac-sha256',
    secret: SecureRandom.base64(32),
    user: nil
  )
    DnsTsigKey.create!(
      name: name,
      algorithm: algorithm,
      secret: secret,
      user: user
    )
  end

  def create_dns_zone_transfer!(
    dns_zone:,
    host_ip_address:,
    peer_type:,
    dns_tsig_key: nil,
    confirmed: :confirmed
  )
    DnsZoneTransfer.create!(
      dns_zone: dns_zone,
      host_ip_address: host_ip_address,
      peer_type: peer_type,
      dns_tsig_key: dns_tsig_key,
      confirmed: DnsZoneTransfer.confirmed(confirmed)
    )
  end

  def create_dns_update_token_record!(dns_zone:, **attrs)
    Token.for_new_record! do |token|
      create_dns_record!(
        dns_zone: dns_zone,
        **attrs.merge(update_token: token)
      )
    end
  end

  def create_reverse_dns_zone!(
    name: '2.0.192.in-addr.arpa.',
    network_address: '192.0.2.0',
    network_prefix: 24
  )
    DnsZone.create!(
      name: name,
      zone_role: :reverse_role,
      zone_source: :internal_source,
      enabled: true,
      label: '',
      default_ttl: 3600,
      email: 'dns@example.test',
      reverse_network_address: network_address,
      reverse_network_prefix: network_prefix
    )
  end

  def create_ipv4_address_in_network!(network:, location:, user: nil, network_interface: nil)
    unless network.ip_version == 4 && network.prefix == 24
      raise ArgumentError, 'create_ipv4_address_in_network! expects an IPv4 /24 network'
    end

    host_octet = ((IpAddress.maximum(:id).to_i % 200) + 20)
    addr = "#{network.address.split('.').first(3).join('.')}.#{host_octet}"

    create_ip_address!(
      network: network,
      location: location,
      user: user,
      addr: addr,
      network_interface: network_interface
    )
  end

  def use_chain_method_in_root!(chain_class, method:, args: [], kwargs: {})
    chain = build_transaction_chain!(name: chain_class.chain_name)
    _child, ret = chain_class.use_in(
      chain,
      args: args,
      kwargs: kwargs,
      method: method
    )
    [chain, ret]
  end
end

RSpec.configure do |config|
  config.include NetworkExportDnsChainSpecHelpers
end
