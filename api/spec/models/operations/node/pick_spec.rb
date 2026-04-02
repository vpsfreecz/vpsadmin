# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'

RSpec.describe VpsAdmin::API::Operations::Node::Pick do
  let(:environment) { SpecSeed.environment }
  let(:location) { SpecSeed.location }

  it 'returns the first ordered node that has an eligible pool for required diskspace' do
    node_a = create_node!
    node_b = create_node!

    create_hypervisor_pool!(
      node: node_a,
      total_space: 10_000,
      used_space: 9_500,
      available_space: 500,
      checked_at: Time.now.utc
    )
    create_hypervisor_pool!(
      node: node_b,
      total_space: 10_000,
      used_space: 7_000,
      available_space: 3_000,
      checked_at: Time.now.utc
    )

    allow(Node).to receive(:pick_by_environment).and_return([node_a, node_b])

    picked = described_class.run(
      environment: environment,
      required_diskspace: 1_000
    )

    expect(picked).to eq(node_b)
  end

  it 'skips earlier nodes whose pools cannot fit the request' do
    node_a = create_node!
    node_b = create_node!

    create_hypervisor_pool!(
      node: node_a,
      total_space: 10_000,
      used_space: 9_500,
      available_space: 500,
      checked_at: Time.now.utc
    )
    create_hypervisor_pool!(
      node: node_b,
      total_space: 10_000,
      used_space: 6_000,
      available_space: 4_000,
      checked_at: Time.now.utc
    )

    allow(Node).to receive(:pick_by_location).and_return([node_a, node_b])

    picked = described_class.run(
      location: location,
      required_diskspace: 1_500
    )

    expect(picked).to eq(node_b)
  end

  it 'preserves existing behavior when required diskspace is omitted' do
    node_a = create_node!
    node_b = create_node!

    allow(Node).to receive(:pick_by_environment).and_return([node_a, node_b])

    picked = described_class.run(environment: environment)

    expect(picked).to eq(node_a)
  end

  private

  def create_node!
    suffix = SecureRandom.hex(4)

    Node.create!(
      name: "node-pick-#{suffix}",
      location: location,
      role: :node,
      hypervisor_type: :vpsadminos,
      ip_addr: "192.0.2.#{100 + SecureRandom.random_number(100)}",
      max_vps: 10,
      cpus: 4,
      total_memory: 4096,
      total_swap: 1024,
      active: true
    )
  end

  def create_hypervisor_pool!(node:, total_space:, used_space:, available_space:, checked_at:)
    pool = create_pool!(node: node, role: :hypervisor, max_datasets: 10)

    pool.update!(
      state: :online,
      total_space: total_space,
      used_space: used_space,
      available_space: available_space,
      checked_at: checked_at
    )

    pool
  end
end
