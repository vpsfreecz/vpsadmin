# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::NetworkInterface::DelRoute do
  around do |example|
    with_current_context do
      example.run
    end
  end

  let(:user) { SpecSeed.user }

  def create_dns_primary(host, zone: create_dns_zone!(user: user, source: :external_source))
    if zone.dns_server_zones.empty?
      create_dns_server_zone!(
        dns_zone: zone, dns_server: create_dns_server!(node: SpecSeed.node), zone_type: :secondary_type
      )
    end
    create_dns_zone_transfer!(
      dns_zone: zone, host_ip_address: host, peer_type: :primary_type,
      dns_tsig_key: create_dns_tsig_key!(user: user)
    )
  end

  [4, 6].product([true, false]).each do |version, ownership|
    it "retains owned IPv#{version} hosts and DNS primaries with ownership policy #{ownership}" do
      fixture = create_netif_vps_fixture!(user: user)
      env = fixture[:vps].node.location.environment
      env.update!(user_ip_ownership: ownership)
      network = create_private_network!(split_prefix: 29, role: :public_access, purpose: :vps)
      if version == 6
        network = SpecSeed.network_v6
        network.update!(split_prefix: 120)
      end
      ip = create_ip_address!(
        network: network, user: user, network_interface: fixture[:netif],
        addr: version == 4 ? network.address : '2001:db8::', size: version == 4 ? 8 : 256
      )
      default_host = ip.host_ip_addresses.take!
      default_host.update!(order: 0)
      extra_host = HostIpAddress.create!(
        ip_address: ip, ip_addr: version == 4 ? network.address.sub(/0\z/, '2') : '2001:db8::10',
        user_created: true
      )
      transfers = [default_host, extra_host].map { |host| create_dns_primary(host) }
      before = transfers.map(&:attributes)
      generations = transfers.map { |transfer| transfer.dns_zone.primary_transfer_generation }
      states = transfers.map do |transfer|
        DnsServerZonePrimaryTransferState.create!(
          dns_server_zone: transfer.dns_zone.dns_server_zones.first, dns_zone_transfer: transfer,
          status: :success, last_attempt_kind: :ixfr_probe, last_attempt_at: Time.current,
          last_success_at: Time.current, last_event_key: SecureRandom.hex(16),
          configuration_generation: transfer.dns_zone.primary_transfer_generation
        )
      end
      state_before = states.map(&:attributes)
      config = user.environment_user_configs.find_by!(environment: env)
      usage = config.public_send(version == 4 ? :ipv4 : :ipv6)

      chain, = described_class.fire(fixture[:netif], [ip])

      expect(transfers.map { |transfer| transfer.reload.attributes }).to eq(before)
      expect(transfers.map { |transfer| transfer.dns_zone.reload.primary_transfer_generation }).to eq(generations)
      expect(states.map { |state| state.reload.attributes }).to eq(state_before)
      expect(tx_classes(chain)).not_to include(Transactions::DnsServerZone::RemoveServers)
      expect(ip.reload.user_id).to eq(user.id)
      expect(ip.charged_environment_id).to eq(env.id)
      expect(config.reload.public_send(version == 4 ? :ipv4 : :ipv6)).to eq(usage)
      edits = confirmations_for(chain)
      expect(edits.where(class_name: %w[DnsZoneTransfer ClusterResourceUse])).to be_empty
      expect(edits.where(class_name: 'HostIpAddress').map(&:confirm_type)).to eq(['edit_after_type'])
      expect(edits.find_by!(class_name: 'IpAddress').attr_changes).to eq(
        'network_interface_id' => nil, 'route_via_id' => nil, 'order' => nil
      )
      expect(extra_host.reload).to be_persisted
    end
  end

  [true, false].each do |ownership|
    it "keeps references and quota on a same-owner VPS move with ownership policy #{ownership}" do
      source = create_netif_vps_fixture!(user: user)
      destination = create_netif_vps_fixture!(user: user)
      source[:vps].node.location.environment.update!(user_ip_ownership: ownership)
      destination[:vps].node.location.environment.reload
      ip = create_ip_address!(user: user, network_interface: source[:netif])
      host = ip.host_ip_addresses.take!
      transfer = create_dns_primary(host)
      before = transfer.attributes
      chain, = described_class.fire(source[:netif], [ip])
      # Apply the route edits as the node's successful confirmation would.
      confirmations_for(chain).where(class_name: 'IpAddress').each do |edit|
        IpAddress.where(edit.row_pks).update_all(edit.attr_changes)
      end
      chain.release_locks

      move, = TransactionChains::NetworkInterface::AddRoute.fire(destination[:netif], [ip.reload])

      expect(transfer.reload.attributes).to eq(before)
      expect(tx_classes(move)).not_to include(Transactions::DnsServerZone::AddServers)
      expect(confirmations_for(move).where(class_name: 'ClusterResourceUse')).to be_empty
      expect(confirmations_for(move).find_by!(class_name: 'IpAddress').attr_changes).to include(
        'network_interface_id' => destination[:netif].id
      )
    end
  end

  [true, false].each do |ownership|
    it "removes unowned references with ownership policy #{ownership}" do
      fixture = create_netif_vps_fixture!(user: user)
      env = fixture[:vps].node.location.environment
      env.update!(user_ip_ownership: ownership)
      ip = create_ip_address!(network_interface: fixture[:netif])
      unless ownership
        config = user.environment_user_configs.find_by!(environment: env)
        config.adjust_resource!(
          :ipv4, delta: ip.size.to_i, user: user, save: true, confirmed: ClusterResourceUse.confirmed(:confirmed)
        )
      end
      transfers = Array.new(2) { create_dns_primary(ip.host_ip_addresses.take!) }

      chain, = described_class.fire(fixture[:netif], [ip])

      expect(transfers.map { |transfer| transfer.reload.confirmed }).to all(eq(:confirm_destroy))
      expect(confirmations_for(chain).where(class_name: 'DnsZoneTransfer').pluck(:confirm_type))
        .to eq(%w[destroy_type destroy_type])
      expect(tx_classes(chain).count(Transactions::DnsServerZone::RemoveServers)).to eq(2)
    end
  end

  it 'does not reallocate cluster resources when no IPs are being removed' do
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    _dataset, dip = create_dataset_with_pool!(
      user: user,
      pool: pool,
      name: "del-route-#{SecureRandom.hex(4)}"
    )
    vps = create_vps_for_dataset!(user: user, node: pool.node, dataset_in_pool: dip)
    netif = NetworkInterface.create!(
      vps: vps,
      name: 'eth0',
      kind: :veth_routed,
      enable: true,
      max_tx: 0,
      max_rx: 0
    )
    ip = IpAddress.create!(
      network: SpecSeed.network_v4,
      ip_addr: '192.0.2.50',
      prefix: SpecSeed.network_v4.split_prefix,
      size: 1,
      network_interface: netif
    )
    HostIpAddress.create!(
      ip_address: ip,
      ip_addr: '192.0.2.50',
      auto_add: true,
      order: nil
    )
    user_env = vps.user.environment_user_configs.find_by!(
      environment: vps.node.location.environment
    )
    user_env.reallocate_resource!(
      :ipv4,
      user_env.ipv4 + 1,
      user: user,
      save: true,
      confirmed: ClusterResourceUse.confirmed(:confirmed)
    )
    configs = vps.user.environment_user_configs

    allow(vps.user).to receive(:environment_user_configs).and_return(configs)
    allow(configs).to receive(:find_by!)
      .with(environment: vps.node.location.environment)
      .and_return(user_env)
    allow(user_env).to receive(:adjust_resource!)
      .and_wrap_original do |orig, resource, *args, **kwargs|
        raise 'unexpected resource reallocation' \
          if %i[ipv4_private ipv6].include?(resource.to_sym)

        orig.call(resource, *args, **kwargs)
      end

    expect { described_class.fire(netif, [ip]) }.not_to raise_error
  end

  it 'rejects an internal removal selected before the address moved to another interface' do
    fixture = create_netif_vps_fixture!(user: user)
    other = create_netif_vps_fixture!(user: SpecSeed.other_user)
    ip = create_ip_address!(network_interface: fixture[:netif])
    config = user.environment_user_configs.find_by!(environment: SpecSeed.environment)
    before = config.ipv4
    IpAddress.where(id: ip.id).update_all(network_interface_id: other[:netif].id)

    expect { described_class.fire(fixture[:netif], [ip]) }
      .to raise_error(VpsAdmin::API::Exceptions::IpAddressNotAssigned)
    expect(config.reload.ipv4).to eq(before)
    expect(ip.reload.network_interface_id).to eq(other[:netif].id)
  end
end
