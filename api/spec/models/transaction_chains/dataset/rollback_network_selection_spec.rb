# frozen_string_literal: true

require 'securerandom'
require 'spec_helper'

RSpec.describe TransactionChains::Dataset::Rollback do
  around do |example|
    with_current_context do
      example.run
    end
  end

  let(:user) { SpecSeed.user }

  def build_fixture!
    primary_pool = create_pool!(node: SpecSeed.node, role: :primary)
    backup_pool = create_pool!(node: SpecSeed.other_node, role: :backup)
    create_port_reservations!(node: primary_pool.node)
    create_port_reservations!(node: backup_pool.node)

    dataset, primary, backup = create_dataset_pair!(
      user: user,
      pool: primary_pool,
      backup_pool: backup_pool,
      name: "rollback-#{SecureRandom.hex(4)}"
    )

    tree = create_tree!(dip: backup, index: 0, head: true)
    branch = create_branch!(tree: tree, name: 'head', head: true)

    snap1, = create_snapshot!(dataset: dataset, dip: primary, name: 'snap-1')
    attach_snapshot_to_branch!(sip: mirror_snapshot!(snapshot: snap1, dip: backup), branch: branch)

    snap2 = Snapshot.create!(
      dataset: dataset,
      name: 'snap-2',
      history_id: dataset.current_history_id,
      confirmed: Snapshot.confirmed(:confirmed)
    )

    backup_sip2 = mirror_snapshot!(snapshot: snap2, dip: backup)
    attach_snapshot_to_branch!(sip: backup_sip2, branch: branch)

    [primary, snap2]
  end

  def rollback_addrs_for(chain)
    transactions_for(chain).filter_map do |tx|
      next unless [Transactions::Storage::Recv.t_type, Transactions::Storage::Send.t_type].include?(tx.handle)

      JSON.parse(tx.input).dig('input', 'addr')
    end.uniq
  end

  it 'uses destination-side primary ips for the pre-restore backup and restore without a pairwise connection' do
    primary, snap2 = build_fixture!

    chain, = described_class.fire(primary, snap2)

    expect(rollback_addrs_for(chain)).to eq([
                                              SpecSeed.other_node.ip_addr,
                                              SpecSeed.node.ip_addr
                                            ])
  end

  it 'uses destination-side pairwise transfer ips for the pre-restore backup and restore' do
    primary, snap2 = build_fixture!

    NodeTransferConnection.create!(
      node_a: SpecSeed.node,
      node_b: SpecSeed.other_node,
      node_a_ip_addr: '10.0.0.15',
      node_b_ip_addr: '10.0.0.16'
    )

    chain, = described_class.fire(primary, snap2)

    expect(rollback_addrs_for(chain)).to eq(['10.0.0.16', '10.0.0.15'])
  end
end
