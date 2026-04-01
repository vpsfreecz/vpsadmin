# frozen_string_literal: true

require 'securerandom'
require 'spec_helper'

RSpec.describe Transactions::Vps::SendConfig do
  around do |example|
    with_current_context do
      example.run
    end
  end

  let(:src_node) { SpecSeed.node }
  let(:dst_node) { SpecSeed.other_node }
  let(:user) { SpecSeed.user }

  def build_vps_fixture!
    src_pool = create_pool!(node: src_node, role: :hypervisor)
    dst_pool = create_pool!(node: dst_node, role: :hypervisor)
    _, dip = create_dataset_with_pool!(user: user, pool: src_pool, name: "rootfs-#{SecureRandom.hex(4)}")
    vps = create_vps_for_dataset!(user: user, node: src_node, dataset_in_pool: dip)
    [vps, dst_pool]
  end

  it 'uses the destination node primary ip without a pairwise connection' do
    vps, dst_pool = build_vps_fixture!

    tx = described_class.fire_chained(
      build_transaction_chain!,
      nil,
      urgent: false,
      args: [vps, dst_node, dst_pool],
      kwargs: { network_interfaces: true }
    )

    payload = JSON.parse(tx.input).fetch('input')
    expect(payload.fetch('node')).to eq(dst_node.ip_addr)
  end

  it 'uses the destination-side transfer ip when present' do
    vps, dst_pool = build_vps_fixture!

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
      args: [vps, dst_node, dst_pool],
      kwargs: { network_interfaces: true }
    )

    payload = JSON.parse(tx.input).fetch('input')
    expect(payload.fetch('node')).to eq('10.0.0.16')
  end
end
