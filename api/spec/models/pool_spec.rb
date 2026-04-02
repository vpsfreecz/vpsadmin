# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'

RSpec.describe Pool do
  let(:node) { create_node! }
  let(:now) { Time.now.utc }

  it 'prefers lower projected fill in live mode' do
    preferred = create_hypervisor_pool!(
      total_space: 10_000,
      used_space: 1_000,
      available_space: 9_000,
      checked_at: now
    )
    fallback = create_hypervisor_pool!(
      total_space: 20_000,
      used_space: 14_000,
      available_space: 6_000,
      checked_at: now
    )

    4.times do |i|
      create_dataset_with_pool!(
        user: SpecSeed.user,
        pool: preferred,
        name: "preferred-#{i}-#{SecureRandom.hex(2)}"
      )
    end

    pools = described_class.pick_by_node(
      node,
      role: :hypervisor,
      required_diskspace: 2_000
    )

    expect(pools.map(&:id)).to eq([preferred.id, fallback.id])
  end

  it 'skips pools without enough free space in live mode' do
    smaller = create_hypervisor_pool!(
      total_space: 10_000,
      used_space: 9_500,
      available_space: 500,
      checked_at: now
    )
    larger = create_hypervisor_pool!(
      total_space: 20_000,
      used_space: 15_000,
      available_space: 5_000,
      checked_at: now
    )

    pools = described_class.pick_by_node(
      node,
      role: :hypervisor,
      required_diskspace: 1_000
    )

    expect(pools.map(&:id)).to eq([larger.id])
    expect(pools).not_to include(smaller)
  end

  it 'uses only online and degraded pools when live metrics are available' do
    online = create_hypervisor_pool!(
      state: :online,
      total_space: 10_000,
      used_space: 1_000,
      available_space: 9_000,
      checked_at: now
    )
    degraded = create_hypervisor_pool!(
      state: :degraded,
      total_space: 10_000,
      used_space: 2_000,
      available_space: 8_000,
      checked_at: now
    )
    faulted = create_hypervisor_pool!(
      state: :faulted,
      total_space: 10_000,
      used_space: 500,
      available_space: 9_500,
      checked_at: now
    )

    pools = described_class.pick_by_node(
      node,
      role: :hypervisor,
      required_diskspace: 1_000
    )

    expect(pools.map(&:id)).to eq([online.id, degraded.id])
    expect(pools).not_to include(faulted)
  end

  it 'falls back to legacy dataset pressure ordering when no fresh metrics exist' do
    preferred = create_hypervisor_pool!
    other = create_hypervisor_pool!(state: :faulted)

    create_dataset_with_pool!(
      user: SpecSeed.user,
      pool: other,
      name: "legacy-#{SecureRandom.hex(3)}"
    )

    pools = described_class.pick_by_node(
      node,
      role: :hypervisor,
      required_diskspace: 2_000
    )

    expect(pools.map(&:id)).to eq([preferred.id, other.id])
  end

  it 'ignores stale metrics when deciding whether live mode is available' do
    stale = create_hypervisor_pool!(
      total_space: 10_000,
      used_space: 500,
      available_space: 9_500,
      checked_at: now - (described_class::ALLOCATION_STATUS_MAX_AGE + 1)
    )
    fallback = create_hypervisor_pool!

    5.times do |i|
      create_dataset_with_pool!(
        user: SpecSeed.user,
        pool: stale,
        name: "stale-#{i}-#{SecureRandom.hex(2)}"
      )
    end

    create_dataset_with_pool!(
      user: SpecSeed.user,
      pool: fallback,
      name: "fallback-#{SecureRandom.hex(2)}"
    )

    pools = described_class.pick_by_node(
      node,
      role: :hypervisor,
      required_diskspace: 1_000
    )

    expect(pools.first).to eq(fallback)
  end

  it 'raises a clear error when no pool fits the requested diskspace' do
    create_hypervisor_pool!(
      total_space: 10_000,
      used_space: 9_500,
      available_space: 500,
      checked_at: now
    )

    expect do
      described_class.take_by_node!(
        node,
        role: :hypervisor,
        required_diskspace: 1_000
      )
    end.to raise_error(
      RuntimeError,
      "no suitable pool available on #{node.domain_name} for 1000 MiB"
    )
  end

  private

  def create_node!
    suffix = SecureRandom.hex(4)

    Node.create!(
      name: "pool-spec-#{suffix}",
      location: SpecSeed.location,
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

  def create_hypervisor_pool!(state: :online, total_space: nil, used_space: nil,
                              available_space: nil, checked_at: nil)
    pool = create_pool!(node: node, role: :hypervisor, max_datasets: 10)

    pool.update!(
      state: state,
      total_space: total_space,
      used_space: used_space,
      available_space: available_space,
      checked_at: checked_at
    )

    pool
  end
end
