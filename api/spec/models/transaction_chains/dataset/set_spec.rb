# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Dataset::Set do
  around do |example|
    with_current_context { example.run }
  end

  let(:user) { SpecSeed.user }

  def confirmation_rows(chain)
    confirmations_for(chain).map do |row|
      [row.class_name, row.row_pks, row.attr_changes]
    end
  end

  def ensure_diskspace_resource!(user:, environment:, value: 1_000_000)
    resource = ClusterResource.find_by!(name: 'diskspace')
    record = UserClusterResource.find_or_initialize_by(
      user: user,
      environment: environment,
      cluster_resource: resource
    )
    record.value = value
    record.save! if record.changed?
    record
  end

  it 'plans edits only for selected properties and reallocation for top-level quota changes' do
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    dataset, dip = create_dataset_with_pool!(user: user, pool: pool, name: "set-#{SecureRandom.hex(4)}")
    atime_prop = dip.dataset_properties.find_by!(name: 'atime')
    quota_prop = dip.dataset_properties.find_by!(name: 'quota')
    compression_prop = dip.dataset_properties.find_by!(name: 'compression')
    ensure_diskspace_resource!(user: user, environment: pool.node.location.environment)
    use = dip.allocate_resource!(
      :diskspace,
      4096,
      user: user,
      confirmed: ClusterResourceUse.confirmed(:confirmed)
    )

    chain, = described_class.fire(
      dip,
      { atime: true, quota: 2048 },
      {}
    )
    rows = confirmation_rows(chain)

    expect(tx_classes(chain)).to eq([Transactions::Storage::SetDataset])
    expect(rows).to include(
      ['DatasetProperty', { 'id' => atime_prop.id }, { 'value' => YAML.dump(true) }],
      ['DatasetProperty', { 'id' => atime_prop.id }, { 'inherited' => 0 }],
      ['DatasetProperty', { 'id' => quota_prop.id }, { 'value' => YAML.dump(2048) }],
      ['DatasetProperty', { 'id' => quota_prop.id }, { 'inherited' => 0 }],
      ['ClusterResourceUse', { 'id' => use.id }, { 'value' => 2048 }]
    )
    expect(
      rows.any? do |row|
        row[0] == 'DatasetProperty' && row[1] == { 'id' => compression_prop.id }
      end
    ).to be(false)
  end

  it 'propagates inheritable property edits to inherited children' do
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    parent, parent_dip = create_dataset_with_pool!(
      user: user,
      pool: pool,
      name: "set-parent-#{SecureRandom.hex(4)}"
    )
    child, child_dip = create_dataset_with_pool!(
      user: user,
      pool: pool,
      parent: parent,
      name: 'child'
    )
    parent_prop = parent_dip.dataset_properties.find_by!(name: 'atime')
    child_prop = child_dip.dataset_properties.find_by!(name: 'atime')

    chain, = described_class.fire(
      parent_dip,
      { atime: true },
      {}
    )
    rows = confirmation_rows(chain)

    expect(tx_classes(chain)).to eq([Transactions::Storage::SetDataset])
    expect(rows).to include(
      ['DatasetProperty', { 'id' => parent_prop.id }, { 'value' => YAML.dump(true) }],
      ['DatasetProperty', { 'id' => parent_prop.id }, { 'inherited' => 0 }],
      ['DatasetProperty', { 'id' => child_prop.id }, { 'value' => YAML.dump(true) }]
    )
    expect(child.reload.parent).to eq(parent)
  end
end
