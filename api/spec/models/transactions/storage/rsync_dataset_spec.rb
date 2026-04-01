# frozen_string_literal: true

require 'securerandom'
require 'spec_helper'

RSpec.describe Transactions::Storage::RsyncDataset do
  around do |example|
    with_current_context do
      example.run
    end
  end

  let(:src_node) { SpecSeed.node }
  let(:dst_node) { SpecSeed.other_node }
  let(:user) { SpecSeed.user }

  def build_dataset_fixture!
    src_pool = create_pool!(node: src_node, role: :primary)
    dst_pool = create_pool!(node: dst_node, role: :primary)
    _, src, dst = create_dataset_pair!(
      user: user,
      pool: src_pool,
      backup_pool: dst_pool,
      name: "rsync-dataset-#{SecureRandom.hex(4)}"
    )
    [src, dst]
  end

  it 'uses the source node primary ip without a pairwise connection' do
    src, dst = build_dataset_fixture!

    tx = described_class.fire_chained(
      build_transaction_chain!,
      nil,
      urgent: false,
      args: [src, dst],
      kwargs: { allow_partial: true }
    )

    payload = JSON.parse(tx.input).fetch('input')
    expect(payload.fetch('src_addr')).to eq(src_node.ip_addr)
  end

  it 'uses the source-side transfer ip when present' do
    src, dst = build_dataset_fixture!

    NodeTransferConnection.create!(
      node_a: src_node,
      node_b: dst_node,
      node_a_ip_addr: '10.0.0.15',
      node_b_ip_addr: '10.0.0.16'
    )

    tx = described_class.fire_chained(
      build_transaction_chain!,
      nil,
      urgent: false,
      args: [src, dst],
      kwargs: { allow_partial: true }
    )

    payload = JSON.parse(tx.input).fetch('input')
    expect(payload.fetch('src_addr')).to eq('10.0.0.15')
  end
end
