# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Export::AddHosts do
  around do |example|
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  it 'adds only IPv4 hosts and confirms each host creation' do
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    dataset, dip = create_dataset_with_pool!(
      user: user,
      pool: pool,
      name: "export-hosts-#{SecureRandom.hex(4)}"
    )
    export, = create_export_for_dataset!(dataset_in_pool: dip)
    ipv4 = create_ip_address!(network: SpecSeed.network_v4, location: pool.node.location)
    ipv6 = create_ip_address!(
      network: SpecSeed.network_v6,
      location: SpecSeed.other_location,
      addr: "2001:db8::#{IpAddress.maximum(:id).to_i + 20}"
    )
    hosts = [
      ExportHost.new(export: export, ip_address: ipv4, rw: true, sync: true, subtree_check: false, root_squash: false),
      ExportHost.new(export: export, ip_address: ipv6, rw: true, sync: true, subtree_check: false, root_squash: false)
    ]

    chain, created_hosts = described_class.fire(export, hosts)

    expect(tx_classes(chain)).to eq([Transactions::Export::AddHosts])
    expect(created_hosts.map(&:ip_address_id)).to eq([ipv4.id])
    expect(tx_payload(chain, Transactions::Export::AddHosts).fetch('hosts').map { |host| host.fetch('address') }).to eq(
      [ipv4.to_s]
    )
    expect(confirmations_for(chain).select { |row| row.class_name == 'ExportHost' }.map(&:confirm_type)).to eq(
      ['just_create_type']
    )
  end
end
