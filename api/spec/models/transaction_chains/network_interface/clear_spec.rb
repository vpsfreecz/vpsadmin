# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::NetworkInterface::Clear do
  around do |example|
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  it 'removes routed-via addresses before directly routed addresses' do
    fixture = create_netif_vps_fixture!(
      user: user,
      dataset_name: "netif-clear-#{SecureRandom.hex(4)}"
    )
    fixture[:vps].node.location.environment.update!(user_ip_ownership: true)

    via_parent_ip = create_ip_address!(
      network: SpecSeed.network_v4,
      location: fixture[:pool].node.location,
      addr: '192.0.2.95'
    )
    via_addr = via_parent_ip.host_ip_addresses.take!

    routed_via = create_ip_address!(
      network: SpecSeed.network_v4,
      location: fixture[:pool].node.location,
      network_interface: fixture[:netif],
      addr: '192.0.2.96'
    )
    routed_via.update!(route_via_id: via_addr.id, order: 0)

    routed_direct = create_ip_address!(
      network: SpecSeed.network_v4,
      location: fixture[:pool].node.location,
      network_interface: fixture[:netif],
      addr: '192.0.2.97'
    )
    routed_direct.update!(order: 1)

    chain, = described_class.fire(fixture[:netif])

    del_route_payloads = transactions_for(chain).filter_map do |tx|
      next unless Transaction.for_type(tx.handle) == Transactions::NetworkInterface::DelRoute

      JSON.parse(tx.input).fetch('input')
    end

    expect(del_route_payloads.map { |payload| payload.fetch('addr') }).to eq(
      [routed_via.addr, routed_direct.addr]
    )
  end

  [described_class, TransactionChains::Vps::SoftDelete, TransactionChains::Vps::Destroy].each do |operation|
    it "combines via/direct route deductions across interfaces in #{operation}" do
      unlock_transaction_signer!
      fixture = build_standalone_vps_fixture(user: user, hostname: 'clear-accounting')
      vps = fixture.fetch(:vps)
      env = vps.node.location.environment
      env.update!(user_ip_ownership: false)
      config = user.environment_user_configs.find_by!(environment: env)
      before = config.ipv4
      netifs = %w[eth0 eth1].map { |name| create_network_interface!(vps, name: name) }
      gateway = create_ip_address!(addr: '192.0.2.230').host_ip_addresses.take!
      ips = netifs.each_with_index.flat_map do |netif, index|
        [false, true].map do |via|
          ip = create_ip_address!(network_interface: netif, addr: "192.0.2.#{231 + (index * 2) + (via ? 1 : 0)}")
          ip.update!(route_via_id: via ? gateway.id : nil)
          ip
        end
      end
      config.adjust_resource!(:ipv4, delta: ips.size, user: user, save: true,
                                     confirmed: ClusterResourceUse.confirmed(:confirmed))
      use = ClusterResourceUse.for_obj(config).joins(user_cluster_resource: :cluster_resource)
                              .find_by!(cluster_resources: { name: 'ipv4' })

      chain, = if operation == described_class
                 operation.fire(netifs)
               else
                 operation.fire(vps, true, nil, nil)
               end

      deductions = confirmations_for(chain).select do |row|
        row.class_name == 'ClusterResourceUse' && row.row_pks == { 'id' => use.id } &&
          row.attr_changes.has_key?('value')
      end
      expect(deductions.map(&:attr_changes)).to eq([{ 'value' => before }])
      expect(use.reload.value).to eq(before + ips.size)
      expect(ips.map { |ip| ip.reload.network_interface_id }).to all(be_in(netifs.map(&:id)))
    end
  end
end
