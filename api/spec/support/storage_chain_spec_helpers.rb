# frozen_string_literal: true

require 'json'
require 'securerandom'

module StorageChainSpecHelpers
  def create_pool!(node:, role:, filesystem: nil, label: nil, is_open: true, max_datasets: 100,
                   refquota_check: false)
    Pool.new(
      node: node,
      role: role,
      filesystem: filesystem || "spec_#{role}_#{SecureRandom.hex(4)}",
      label: label || "Spec #{role} #{SecureRandom.hex(4)}",
      is_open: is_open,
      max_datasets: max_datasets,
      refquota_check: refquota_check
    ).tap(&:save!)
  end

  def attach_dataset_to_pool!(dataset:, pool:, label: nil, confirmed: :confirmed)
    seed_pool_dataset_properties!(pool)

    DatasetInPool.create!(
      dataset: dataset,
      pool: pool,
      label: label,
      confirmed: DatasetInPool.confirmed(confirmed)
    )
  end

  def create_dataset_pair!(user:, pool:, backup_pool: nil, name: nil, label: nil, backup_label: nil)
    dataset, primary_dip = create_dataset_with_pool!(
      user: user,
      pool: pool,
      name: name || "storage-root-#{SecureRandom.hex(4)}",
      label: label
    )

    backup_dip =
      if backup_pool
        attach_dataset_to_pool!(
          dataset: dataset,
          pool: backup_pool,
          label: backup_label
        )
      end

    [dataset, primary_dip, backup_dip]
  end

  def create_port_reservations!(node:, count: 20, start_port: nil)
    start_port ||= (PortReservation.maximum(:port) || 39_000) + 1

    count.times.map do |i|
      PortReservation.create!(
        node: node,
        port: start_port + i
      )
    end
  end

  def reserve_test_port!(node:, addr: nil, port: nil)
    PortReservation.create!(
      node: node,
      addr: addr || node.addr,
      port: port || ((PortReservation.maximum(:port) || 39_000) + 1)
    )
  end

  def mirror_snapshot!(snapshot:, dip:, reference_count: 0, confirmed: :confirmed)
    SnapshotInPool.create!(
      snapshot: snapshot,
      dataset_in_pool: dip,
      reference_count: reference_count,
      confirmed: SnapshotInPool.confirmed(confirmed)
    )
  end

  def create_tree!(dip:, index: 0, head: true, confirmed: :confirmed)
    DatasetTree.create!(
      dataset_in_pool: dip,
      index: index,
      head: head,
      confirmed: DatasetTree.confirmed(confirmed)
    )
  end

  def create_branch!(tree:, name:, index: 0, head: true, confirmed: :confirmed)
    Branch.create!(
      dataset_tree: tree,
      name: name,
      index: index,
      head: head,
      confirmed: Branch.confirmed(confirmed)
    )
  end

  def attach_snapshot_to_branch!(sip:, branch:, parent_entry: nil, confirmed: :confirmed)
    SnapshotInPoolInBranch.create!(
      snapshot_in_pool: sip,
      branch: branch,
      snapshot_in_pool_in_branch: parent_entry,
      confirmed: SnapshotInPoolInBranch.confirmed(confirmed)
    )
  end

  def create_backup_branch_snapshot!(snapshot:, dip:, branch:, parent_entry: nil, reference_count: 0,
                                     confirmed: :confirmed)
    sip = mirror_snapshot!(
      snapshot: snapshot,
      dip: dip,
      reference_count: reference_count,
      confirmed: confirmed
    )

    entry = attach_snapshot_to_branch!(
      sip: sip,
      branch: branch,
      parent_entry: parent_entry,
      confirmed: confirmed
    )

    [sip, entry]
  end

  def build_transaction_chain!(name: 'spec_storage_chain')
    chain = TransactionChain.create!(
      name: name,
      type: 'TransactionChain',
      state: :queued,
      size: 0,
      progress: 0,
      user: User.current,
      user_session: UserSession.current,
      urgent_rollback: false
    )

    chain.global_locks = []
    chain.locks = []
    chain.named = {}
    chain.last_id = nil
    chain.last_node_id = nil
    chain.dst_chain = chain
    chain.urgent = false
    chain.prio = 0
    chain.reversible = nil
    chain
  end

  def use_chain_in_root!(chain_class, args: [], kwargs: {})
    chain = build_transaction_chain!
    _, ret = chain_class.use_in(chain, args: args, kwargs: kwargs)
    [chain, ret]
  end

  def create_user_namespace_map!(user: SpecSeed.user, label: nil)
    userns = UserNamespace.create!(
      user: user,
      block_count: 1,
      offset: (UserNamespace.maximum(:offset) || 131_072) + 65_536,
      size: 65_536
    )

    UserNamespaceMap.create!(
      user_namespace: userns,
      label: label || "spec-map-#{SecureRandom.hex(4)}"
    )
  end

  def create_vps_for_dataset!(user:, node:, dataset_in_pool:, hostname: nil, os_template: SpecSeed.os_template,
                              dns_resolver: SpecSeed.dns_resolver, user_namespace_map: nil)
    vps = Vps.new(
      user: user,
      node: node,
      hostname: hostname || "spec-vps-#{SecureRandom.hex(4)}",
      os_template: os_template,
      dns_resolver: dns_resolver,
      dataset_in_pool: dataset_in_pool,
      user_namespace_map: user_namespace_map || create_user_namespace_map!(user: user),
      object_state: :active,
      confirmed: :confirmed
    )

    vps.save!
    vps
  rescue ActiveRecord::RecordInvalid
    vps.save!(validate: false)
    vps
  end

  def transactions_for(chain)
    chain.transactions.order(:id).to_a
  end

  def tx_classes(chain)
    transactions_for(chain).map { |t| Transaction.for_type(t.handle) }
  end

  def tx_payloads(chain)
    transactions_for(chain).map { |t| JSON.parse(t.input).fetch('input') }
  end

  def confirmations_for(chain)
    TransactionConfirmation
      .joins(:parent_transaction)
      .where(transactions: { transaction_chain_id: chain.id })
      .order('transactions.id ASC, transaction_confirmations.id ASC')
  end

  def head_tree!(dip)
    dip.dataset_trees.find_by!(head: true)
  end

  def head_branch!(dip)
    head_tree!(dip).branches.find_by!(head: true)
  end

  def create_doc_branching_fixture!(dataset:, backup_dip:)
    tree = create_tree!(dip: backup_dip, index: 0, head: true)
    old_branch = create_branch!(
      tree: tree,
      name: '2014-01-01T01:00:00',
      index: 0,
      head: false
    )
    new_branch = create_branch!(
      tree: tree,
      name: '2014-01-03T01:00:00',
      index: 0,
      head: true
    )

    entries = {}
    sips = {}
    snaps = {}

    %w[
      2014-01-01T01:00:00
      2014-01-02T01:00:00
      2014-01-03T01:00:00
      2014-01-04T01:00:00
      2014-01-05T01:00:00
      2014-01-06T01:00:00
      2014-01-07T01:00:00
      2014-01-08T01:00:00
    ].each_with_index do |name, idx|
      snap, sip = create_snapshot!(dataset: dataset, dip: backup_dip, name: name)
      snap.update_column(:created_at, Time.utc(2014, 1, idx + 1, 1, 0, 0))

      snaps[name] = snap
      sips[name] = sip
    end

    %w[
      2014-01-01T01:00:00
      2014-01-02T01:00:00
      2014-01-03T01:00:00
      2014-01-06T01:00:00
      2014-01-07T01:00:00
      2014-01-08T01:00:00
    ].each do |name|
      entries[name] = attach_snapshot_to_branch!(
        sip: sips.fetch(name),
        branch: new_branch
      )
    end

    entries['2014-01-04T01:00:00'] = attach_snapshot_to_branch!(
      sip: sips.fetch('2014-01-04T01:00:00'),
      branch: old_branch,
      parent_entry: entries.fetch('2014-01-03T01:00:00')
    )

    entries['2014-01-05T01:00:00'] = attach_snapshot_to_branch!(
      sip: sips.fetch('2014-01-05T01:00:00'),
      branch: old_branch,
      parent_entry: entries.fetch('2014-01-03T01:00:00')
    )

    sips.fetch('2014-01-03T01:00:00').update!(reference_count: 2)

    {
      tree: tree,
      old_branch: old_branch,
      new_branch: new_branch,
      snapshots: snaps,
      snapshot_in_pools: sips,
      entries: entries
    }
  end
end

RSpec.configure do |config|
  config.include StorageChainSpecHelpers
end
