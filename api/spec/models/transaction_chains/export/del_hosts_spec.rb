# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Export::DelHosts do
  around do |example|
    with_current_context(user: user) { example.run }
  end

  let(:user) { SpecSeed.user }

  def create_export_with_hosts
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    dataset, dip = create_dataset_with_pool!(
      user: user,
      pool: pool,
      name: "export-del-hosts-#{SecureRandom.hex(4)}"
    )
    export, = create_export_for_dataset!(dataset_in_pool: dip)
    host1 = ExportHost.create!(
      export: export,
      ip_address: create_ip_address!(network: SpecSeed.network_v4, location: pool.node.location),
      rw: true,
      sync: true,
      subtree_check: false,
      root_squash: false
    )
    host2 = ExportHost.create!(
      export: export,
      ip_address: create_ip_address!(network: SpecSeed.network_v4, location: pool.node.location),
      rw: false,
      sync: true,
      subtree_check: false,
      root_squash: true
    )
    [export, host1, host2]
  end

  it 'removes hosts addressed by ExportHost and IpAddress records' do
    export, host1, host2 = create_export_with_hosts

    chain, = described_class.fire(export, [host1, host2.ip_address])

    expect(tx_classes(chain)).to eq([Transactions::Export::DelHosts])
    expect(tx_payload(chain, Transactions::Export::DelHosts).fetch('hosts').map { |host| host.fetch('address') }).to eq(
      [host1.ip_address.to_s, host2.ip_address.to_s]
    )
    expect(confirmations_for(chain).select { |row| row.class_name == 'ExportHost' }.map(&:confirm_type)).to eq(
      %w[just_destroy_type just_destroy_type]
    )
  end

  it 'is a no-op when there are no matching hosts' do
    export, = create_export_with_hosts

    chain, result = use_chain_in_root!(described_class, args: [export, []])

    expect(result).to be_nil
    expect(chain.transactions).to be_empty
  end
end
