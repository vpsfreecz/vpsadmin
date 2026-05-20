# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Cluster::GenerateMigrationKeys do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  def create_pool_with_status(node:, status: :fresh, migration_public_key: nil, filesystem: nil)
    case status
    when :fresh
      fresh_node_status!(node)
    when :stale
      stale_node_status!(node)
    end

    create_pool!(
      node: node,
      role: :primary,
      filesystem: filesystem || "tank-#{SecureRandom.hex(4)}/migration",
      label: "Migration #{SecureRandom.hex(4)}"
    ).tap do |pool|
      pool.update!(migration_public_key: migration_public_key) if migration_public_key
    end
  end

  it 'generates send keys only for active vpsadminos node pools with fresh status and no key' do
    eligible_node = create_node!(name: "eligible-#{SecureRandom.hex(3)}")
    stale_node = create_node!(name: "stale-#{SecureRandom.hex(3)}")
    inactive_node = create_node!(name: "inactive-#{SecureRandom.hex(3)}")
    storage_node = create_node!(name: "storage-#{SecureRandom.hex(3)}", role: :storage)
    openvz_node = create_node!(name: "openvz-#{SecureRandom.hex(3)}", hypervisor_type: :openvz)
    keyed_node = create_node!(name: "keyed-#{SecureRandom.hex(3)}")

    eligible_pool = create_pool_with_status(node: eligible_node)
    stale_pool = create_pool_with_status(node: stale_node, status: :stale)
    inactive_pool = create_pool_with_status(node: inactive_node)
    inactive_node.update!(active: false)
    storage_pool = create_pool_with_status(node: storage_node)
    openvz_pool = create_pool_with_status(node: openvz_node)
    keyed_pool = create_pool_with_status(
      node: keyed_node,
      migration_public_key: 'ssh-ed25519 EXISTING keyed@test'
    )

    chain, = described_class.fire

    expect(tx_classes(chain)).to eq([Transactions::Pool::GenerateSendKey])
    expect(tx_payload(chain, Transactions::Pool::GenerateSendKey)).to include(
      'pool_id' => eligible_pool.id,
      'pool_ids' => [eligible_pool.id],
      'pool_name' => eligible_pool.name,
      'pool_fs' => eligible_pool.filesystem
    )
    expect(
      tx_payloads(chain).map { |payload| payload.fetch('pool_id') }
    ).not_to include(
      stale_pool.id,
      inactive_pool.id,
      storage_pool.id,
      openvz_pool.id,
      keyed_pool.id
    )
  end

  it 'generates one send key for all pool rows sharing an osctl pool' do
    node = create_node!(name: "shared-#{SecureRandom.hex(3)}")
    shared_a = create_pool_with_status(node: node, filesystem: 'tank/shared-a')
    shared_b = create_pool_with_status(node: node, filesystem: 'tank/shared-b')

    chain, = described_class.fire

    expect(tx_classes(chain)).to eq([Transactions::Pool::GenerateSendKey])
    expect(tx_payload(chain, Transactions::Pool::GenerateSendKey)).to include(
      'pool_id' => shared_a.id,
      'pool_ids' => contain_exactly(shared_a.id, shared_b.id),
      'pool_name' => 'tank'
    )
  end

  it 'regenerates a shared send key when pool rows for one osctl pool disagree' do
    node = create_node!(name: "conflict-#{SecureRandom.hex(3)}")
    shared_a = create_pool_with_status(
      node: node,
      filesystem: 'tank/conflict-a',
      migration_public_key: 'ssh-ed25519 AAAAOLD1 old1@test'
    )
    shared_b = create_pool_with_status(
      node: node,
      filesystem: 'tank/conflict-b',
      migration_public_key: 'ssh-ed25519 AAAAOLD2 old2@test'
    )

    chain, = described_class.fire

    expect(tx_classes(chain)).to eq([Transactions::Pool::GenerateSendKey])
    expect(tx_payload(chain, Transactions::Pool::GenerateSendKey)).to include(
      'pool_ids' => contain_exactly(shared_a.id, shared_b.id),
      'pool_name' => 'tank'
    )
  end
end
