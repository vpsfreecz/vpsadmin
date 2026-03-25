# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Dataset::Inherit do
  around do |example|
    with_current_context { example.run }
  end

  let(:user) { SpecSeed.user }

  def confirmation_rows(chain)
    confirmations_for(chain).map do |row|
      [row.class_name, row.row_pks, row.attr_changes]
    end
  end

  it 'inherits default values on the parent and propagates them to inherited children' do
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    parent, parent_dip = create_dataset_with_pool!(
      user: user,
      pool: pool,
      name: "inherit-parent-#{SecureRandom.hex(4)}"
    )
    _, child_dip = create_dataset_with_pool!(
      user: user,
      pool: pool,
      parent: parent,
      name: 'child'
    )
    parent_prop = parent_dip.dataset_properties.find_by!(name: 'atime')
    child_prop = child_dip.dataset_properties.find_by!(name: 'atime')
    parent_prop.update!(value: true, inherited: false)

    chain, = described_class.fire(parent_dip, [:atime])
    rows = confirmation_rows(chain)

    expect(tx_classes(chain)).to eq([Transactions::Storage::InheritProperty])
    expect(rows).to include(
      [
        'DatasetProperty',
        { 'id' => parent_prop.id },
        { 'inherited' => 1, 'value' => YAML.dump(false) }
      ],
      ['DatasetProperty', { 'id' => child_prop.id }, { 'value' => YAML.dump(false) }]
    )
  end

  it 'ignores properties that are already inherited' do
    pool = create_pool!(node: SpecSeed.node, role: :primary)
    dataset, dip = create_dataset_with_pool!(user: user, pool: pool, name: "inherit-#{SecureRandom.hex(4)}")
    atime_prop = dip.dataset_properties.find_by!(name: 'atime')
    compression_prop = dip.dataset_properties.find_by!(name: 'compression')
    compression_prop.update!(value: false, inherited: false)

    chain, = described_class.fire(dip, %i[atime compression])
    rows = confirmation_rows(chain)

    expect(tx_classes(chain)).to eq([Transactions::Storage::InheritProperty])
    expect(rows).to include(
      [
        'DatasetProperty',
        { 'id' => compression_prop.id },
        { 'inherited' => 1, 'value' => YAML.dump(true) }
      ]
    )
    expect(
      rows.any? do |row|
        row[0] == 'DatasetProperty' && row[1] == { 'id' => atime_prop.id }
      end
    ).to be(false)
  end
end
