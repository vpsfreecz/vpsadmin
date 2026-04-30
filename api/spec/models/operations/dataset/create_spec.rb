# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::Dataset::Create do
  around do |example|
    with_current_context(user: SpecSeed.user) { example.run }
  end

  let(:pool) { create_pool!(node: SpecSeed.node, role: :primary, refquota_check: true) }
  let!(:root_pair) do
    create_dataset_with_pool!(
      user: SpecSeed.user,
      pool: pool,
      name: "data-#{SecureRandom.hex(3)}",
      label: "data-#{SecureRandom.hex(3)}",
      properties: { refquota: 10_240 }
    )
  end
  let(:root_ds) { root_pair.first }
  let(:root_dip) { root_pair.last }
  let(:chain) { instance_double(TransactionChain) }

  def stub_dataset_create_chain
    allow(TransactionChains::Dataset::Create).to receive(:fire) do |_pool, _parent_dip, path, _opts|
      new_ds = path.last
      [chain, [instance_double(DatasetInPool, dataset: new_ds)]]
    end
  end

  before do
    stub_dataset_create_chain
  end

  it 'creates a child under the explicit parent dataset' do
    ret_chain, ret_ds = described_class.run(
      'child',
      root_ds,
      properties: { refquota: 2048 },
      automount: true
    )

    expect(ret_chain).to eq(chain)
    expect(ret_ds.name).to eq('child')
    expect(ret_ds.parent).to eq(root_ds)
    expect(TransactionChains::Dataset::Create).to have_received(:fire) do |arg_pool, parent_dip, path, opts|
      expect(arg_pool).to eq(pool)
      expect(parent_dip).to eq(root_dip)
      expect(path.map(&:name)).to eq(%w[child])
      expect(opts[:properties]).to eq(refquota: 2048)
      expect(opts[:automount]).to be(true)
    end
  end

  it 'creates a child by top-level label lookup when parent is nil' do
    ret_chain, ret_ds = described_class.run(
      "#{root_dip.label}/child",
      nil,
      properties: { refquota: 2048 }
    )

    expect(ret_chain).to eq(chain)
    expect(ret_ds.name).to eq('child')
    expect(TransactionChains::Dataset::Create).to have_received(:fire) do |_pool, parent_dip, path, _opts|
      expect(parent_dip).to eq(root_dip)
      expect(path.map(&:name)).to eq(%w[child])
    end
  end

  it 'raises DatasetLabelDoesNotExist for unknown top-level labels' do
    expect do
      described_class.run('missing-label/child', nil, properties: { refquota: 2048 })
    end.to raise_error(VpsAdmin::API::Exceptions::DatasetLabelDoesNotExist)

    expect(TransactionChains::Dataset::Create).not_to have_received(:fire)
  end

  it 'raises DatasetAlreadyExists when the whole path already exists' do
    create_dataset_with_pool!(
      user: SpecSeed.user,
      pool: pool,
      parent: root_ds,
      name: 'child',
      properties: { refquota: 2048 }
    )

    expect do
      described_class.run('child', root_ds, properties: { refquota: 2048 })
    end.to raise_error(VpsAdmin::API::Exceptions::DatasetAlreadyExists)

    expect(TransactionChains::Dataset::Create).not_to have_received(:fire)
  end

  it 'requires refquota when refquota checks are enabled' do
    expect do
      described_class.run('child', root_ds, properties: {})
    end.to raise_error(VpsAdmin::API::Exceptions::PropertyInvalid, 'refquota must be set')

    expect(TransactionChains::Dataset::Create).not_to have_received(:fire)
  end

  it 'rejects creating more than one nested dataset at once under refquota checks' do
    expect do
      described_class.run('child/grandchild', root_ds, properties: { refquota: 2048 })
    end.to raise_error(VpsAdmin::API::Exceptions::DatasetNestingForbidden)

    expect(TransactionChains::Dataset::Create).not_to have_received(:fire)
  end

  it 'checks VPS and pool maintenance for hypervisor pools and passes user namespace mapping' do
    ensure_available_node_status!(SpecSeed.node)
    hypervisor_pool = create_pool!(node: SpecSeed.node, role: :hypervisor)
    root_ds, root_dip = create_dataset_with_pool!(
      user: SpecSeed.user,
      pool: hypervisor_pool,
      name: "vps-data-#{SecureRandom.hex(3)}",
      properties: { refquota: 10_240 }
    )
    userns_map = create_user_namespace_map!(user: SpecSeed.user)
    vps = create_vps_for_dataset!(
      user: SpecSeed.user,
      node: SpecSeed.node,
      dataset_in_pool: root_dip,
      user_namespace_map: userns_map
    )
    vps.update!(map_mode: :zfs)
    op = described_class.new

    allow(op).to receive(:maintenance_check!)

    ret_chain, ret_ds = op.run('child', root_ds, properties: { refquota: 2048 })

    expect(ret_chain).to eq(chain)
    expect(ret_ds.name).to eq('child')
    expect(op).to have_received(:maintenance_check!).with(vps)
    expect(op).to have_received(:maintenance_check!).with(hypervisor_pool)
    expect(TransactionChains::Dataset::Create).to have_received(:fire) do |_pool, _parent_dip, _path, opts|
      expect(opts[:userns_map]).to eq(userns_map)
    end
  end
end
