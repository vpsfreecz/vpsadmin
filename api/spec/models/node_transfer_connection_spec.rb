# frozen_string_literal: true

require 'spec_helper'

RSpec.describe NodeTransferConnection do
  let(:node_a) { SpecSeed.node }
  let(:node_b) { SpecSeed.other_node }

  it 'normalizes node order and swaps endpoint addresses' do
    conn = described_class.create!(
      node_a: node_b,
      node_b: node_a,
      node_a_ip_addr: '10.0.0.16',
      node_b_ip_addr: '10.0.0.15'
    )

    expect(conn.node_a_id).to eq(node_a.id)
    expect(conn.node_b_id).to eq(node_b.id)
    expect(conn.node_a_ip_addr).to eq('10.0.0.15')
    expect(conn.node_b_ip_addr).to eq('10.0.0.16')
  end

  it 'finds a pair in both node orders' do
    conn = described_class.create!(
      node_a: node_a,
      node_b: node_b,
      node_a_ip_addr: '10.0.0.15',
      node_b_ip_addr: '10.0.0.16'
    )

    expect(described_class.between(node_a, node_b).take).to eq(conn)
    expect(described_class.between(node_b, node_a).take).to eq(conn)
  end

  it 'returns the correct endpoint ip for each node' do
    conn = described_class.create!(
      node_a: node_a,
      node_b: node_b,
      node_a_ip_addr: '10.0.0.15',
      node_b_ip_addr: '10.0.0.16'
    )

    expect(conn.ip_addr_for(node_a)).to eq('10.0.0.15')
    expect(conn.ip_addr_for(node_b)).to eq('10.0.0.16')
  end

  it 'falls back to node.ip_addr when no enabled pairwise connection exists' do
    expect(node_a.transfer_ip_for(node_b)).to eq(node_a.ip_addr)

    described_class.create!(
      node_a: node_a,
      node_b: node_b,
      node_a_ip_addr: '10.0.0.15',
      node_b_ip_addr: '10.0.0.16',
      enabled: false
    )

    expect(node_a.reload.transfer_ip_for(node_b.reload)).to eq(node_a.ip_addr)
  end

  it 'uses the pair-specific local endpoint ip when the connection is enabled' do
    described_class.create!(
      node_a: node_a,
      node_b: node_b,
      node_a_ip_addr: '10.0.0.15',
      node_b_ip_addr: '10.0.0.16'
    )

    expect(node_a.reload.transfer_ip_for(node_b.reload)).to eq('10.0.0.15')
    expect(node_b.reload.transfer_ip_for(node_a.reload)).to eq('10.0.0.16')
  end

  it 'rejects same-node pairs' do
    conn = described_class.new(
      node_a: node_a,
      node_b: node_a,
      node_a_ip_addr: '10.0.0.15',
      node_b_ip_addr: '10.0.0.15'
    )

    expect(conn).not_to be_valid
    expect(conn.errors[:node_b]).to include('must differ from node_a')
  end

  it 'rejects cidr endpoint addresses' do
    conn = described_class.new(
      node_a: node_a,
      node_b: node_b,
      node_a_ip_addr: '10.0.0.15/24',
      node_b_ip_addr: '10.0.0.16'
    )

    expect(conn).not_to be_valid
    expect(conn.errors[:node_a_ip_addr]).to include('must be a plain IPv4 host address')
  end
end
