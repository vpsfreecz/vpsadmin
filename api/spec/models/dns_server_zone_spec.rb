# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'

RSpec.describe DnsServerZone do
  before do
    SpecSeed.user
    SpecSeed.node
    SpecSeed.other_node
    SpecSeed.network_v4
  end

  def create_zone!(user:)
    DnsZone.create!(
      name: "spec-ext-#{SecureRandom.hex(4)}.example.test.",
      user: user,
      zone_role: :forward_role,
      zone_source: :external_source,
      enabled: true,
      label: '',
      default_ttl: 3600,
      email: nil
    )
  end

  def create_dns_server!(name_prefix:, node:, ipv4_addr:)
    DnsServer.create!(
      node: node,
      name: "#{name_prefix}-#{SecureRandom.hex(4)}.example.test",
      ipv4_addr: ipv4_addr,
      ipv6_addr: nil,
      hidden: false,
      enable_user_dns_zones: true,
      user_dns_zone_type: :secondary_type
    )
  end

  def next_host_ip_addr(net)
    used_octets = IpAddress.where(network: net).pluck(:ip_addr).filter_map do |addr|
      next unless addr.start_with?('192.0.2.')

      addr.split('.').last.to_i
    end

    octet = ([149] + used_octets).max + 1
    "192.0.2.#{octet}"
  end

  def create_host_ip_for_user!(user:, ip: nil)
    net = SpecSeed.network_v4
    ip_addr = ip || next_host_ip_addr(net)

    ip_record = IpAddress.create!(
      network: net,
      ip_addr: ip_addr,
      prefix: net.split_prefix,
      size: 1,
      user: user
    )

    HostIpAddress.create!(
      ip_address: ip_record,
      ip_addr: ip_addr,
      order: nil,
      user_created: true
    )
  end

  def create_tsig_key!(user:)
    DnsTsigKey.create!(
      user: user,
      name: "spec-key-#{SecureRandom.hex(4)}",
      algorithm: 'hmac-sha256',
      secret: 'dGVzdA=='
    )
  end

  it 'exposes external peer secondaries as primaries and secondaries without including self' do
    zone = create_zone!(user: SpecSeed.user)
    upstream_host_ip = create_host_ip_for_user!(user: SpecSeed.user)
    tsig_key = create_tsig_key!(user: SpecSeed.user)
    upstream_transfer = DnsZoneTransfer.create!(
      dns_zone: zone,
      host_ip_address: upstream_host_ip,
      peer_type: :primary_type,
      dns_tsig_key: tsig_key
    )
    server_a = create_dns_server!(
      name_prefix: 'ns3',
      node: SpecSeed.node,
      ipv4_addr: '198.51.100.31'
    )
    server_b = create_dns_server!(
      name_prefix: 'ns4',
      node: SpecSeed.other_node,
      ipv4_addr: '198.51.100.32'
    )
    server_a_zone = described_class.create!(
      dns_zone: zone,
      dns_server: server_a,
      zone_type: :secondary_type,
      confirmed: described_class.confirmed(:confirm_create)
    )
    server_b_zone = described_class.create!(
      dns_zone: zone,
      dns_server: server_b,
      zone_type: :secondary_type,
      confirmed: described_class.confirmed(:confirm_create)
    )

    expect(server_a_zone.reload.primaries).to contain_exactly(
      upstream_transfer.server_opts,
      server_b_zone.server_opts
    )
    expect(server_a_zone.secondaries).to contain_exactly(server_b_zone.server_opts)
    expect(server_a_zone.primaries).not_to include(server_a_zone.server_opts)
    expect(server_a_zone.secondaries).not_to include(server_a_zone.server_opts)
  end
end
