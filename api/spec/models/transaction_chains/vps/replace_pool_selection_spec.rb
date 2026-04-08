# frozen_string_literal: true

require 'json'
require 'securerandom'
require 'spec_helper'

RSpec.describe TransactionChains::Vps::Replace::Os do
  around do |example|
    with_current_context do
      unlock_transaction_signer!
      example.run
    end
  end

  let(:user) { SpecSeed.user }
  let(:node) { create_node! }

  it 'uses the selected destination pool for both copy and config population' do
    allow(MailTemplate).to receive(:send_mail!)

    now = Time.now.utc
    dozer = create_hypervisor_pool!(
      node: node,
      filesystem: 'dozer',
      used_space: 1_000,
      available_space: 9_000,
      checked_at: now
    )
    create_hypervisor_pool!(
      node: node,
      filesystem: 'tank',
      used_space: 9_500,
      available_space: 500,
      checked_at: now
    )
    _, dip = create_dataset_with_pool!(
      user: user,
      pool: dozer,
      name: "rootfs-#{SecureRandom.hex(4)}"
    )
    vps = create_vps_for_dataset!(user: user, node: node, dataset_in_pool: dip)
    allocate_dip_diskspace!(dip, user: user, value: 2048)
    allocate_vps_resource!(vps, :cpu, 2)
    allocate_vps_resource!(vps, :memory, 1024)
    allocate_vps_resource!(vps, :swap, 512)

    chain, _dst_vps = described_class.fire(vps, node, start: false)

    copy_payload = tx_payload(chain, Transactions::Vps::Copy)
    config_payload = tx_payload(chain, Transactions::Vps::PopulateConfig)

    expect(copy_payload.fetch('as_pool_name')).to eq('dozer')
    expect(config_payload.fetch('pool_fs')).to eq('dozer')
  end

  private

  def ensure_user_cluster_resource!(user:, environment:, resource:, value: 10_000)
    cluster_resource = ClusterResource.find_by!(name: resource.to_s)
    record = UserClusterResource.find_or_initialize_by(
      user: user,
      environment: environment,
      cluster_resource: cluster_resource
    )
    record.value = value if record.new_record? || record.value.to_i < value
    record.save! if record.changed?
    record
  end

  def allocate_vps_resource!(vps, resource, value)
    ensure_user_cluster_resource!(
      user: vps.user,
      environment: vps.node.location.environment,
      resource: resource,
      value: [value * 2, 10_000].max
    )

    vps.reallocate_resource!(
      resource,
      value,
      user: vps.user,
      save: true,
      confirmed: ::ClusterResourceUse.confirmed(:confirmed)
    )
  end

  def allocate_dip_diskspace!(dip, user:, value:)
    ensure_user_cluster_resource!(
      user: user,
      environment: dip.pool.node.location.environment,
      resource: :diskspace,
      value: [value * 2, 10_000].max
    )

    dip.allocate_resource!(
      :diskspace,
      value,
      user: user,
      confirmed: ::ClusterResourceUse.confirmed(:confirmed),
      admin_override: true
    )
  end

  def tx_payload(chain, tx_class)
    tx = transactions_for(chain).find do |transaction|
      Transaction.for_type(transaction.handle) == tx_class
    end

    expect(tx).not_to be_nil

    JSON.parse(tx.input).fetch('input')
  end

  def create_node!
    suffix = SecureRandom.hex(4)

    Node.create!(
      name: "replace-spec-#{suffix}",
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

  def create_hypervisor_pool!(node:, filesystem:, used_space:, available_space:, checked_at:)
    pool = create_pool!(
      node: node,
      role: :hypervisor,
      filesystem: filesystem,
      max_datasets: 10
    )

    pool.update!(
      state: :online,
      total_space: used_space + available_space,
      used_space: used_space,
      available_space: available_space,
      checked_at: checked_at
    )

    pool
  end
end
