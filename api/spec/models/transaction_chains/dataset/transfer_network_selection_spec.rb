# frozen_string_literal: true

require 'securerandom'
require 'spec_helper'

RSpec.describe TransactionChains::Dataset::Transfer do
  around do |example|
    with_current_context do
      example.run
    end
  end

  let(:user) { SpecSeed.user }

  def build_fixture!
    src_pool = create_pool!(node: SpecSeed.node, role: :primary)
    dst_pool = create_pool!(node: SpecSeed.other_node, role: :backup)
    create_port_reservations!(node: dst_pool.node)

    dataset, src, dst = create_dataset_pair!(
      user: user,
      pool: src_pool,
      backup_pool: dst_pool,
      name: "transfer-#{SecureRandom.hex(4)}"
    )

    create_snapshot!(dataset: dataset, dip: src, name: 'snap-1')
    [src, dst]
  end

  def transfer_addrs_for(chain)
    transactions_for(chain).filter_map do |tx|
      next unless [Transactions::Storage::Recv.t_type, Transactions::Storage::Send.t_type].include?(tx.handle)

      JSON.parse(tx.input).dig('input', 'addr')
    end.uniq
  end

  it 'falls back to the destination node primary ip for send and recv payloads' do
    src, dst = build_fixture!

    chain, = described_class.fire(src, dst)

    expect(transfer_addrs_for(chain)).to eq([SpecSeed.other_node.ip_addr])
  end

  it 'uses the destination-side pairwise transfer ip for send and recv payloads' do
    src, dst = build_fixture!

    NodeTransferConnection.create!(
      node_a: SpecSeed.node,
      node_b: SpecSeed.other_node,
      node_a_ip_addr: '10.0.0.15',
      node_b_ip_addr: '10.0.0.16'
    )

    chain, = described_class.fire(src, dst)

    expect(transfer_addrs_for(chain)).to eq(['10.0.0.16'])
  end
end
