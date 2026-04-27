# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TransactionChains::Pool::Create do
  around do |example|
    unlock_transaction_signer!
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  before do
    ensure_available_node_status!(SpecSeed.node)
  end

  it 'persists the pool, appends create_pool, locks resources, and creates properties' do
    pool = Pool.new(
      node: SpecSeed.node,
      label: "Spec pool #{SecureRandom.hex(3)}",
      filesystem: "tank/spec-#{SecureRandom.hex(3)}",
      role: :primary,
      is_open: true,
      max_datasets: 100,
      refquota_check: true
    )
    property_registry = VpsAdmin::API::DatasetProperties::Registrator.properties

    chain, created = described_class.fire(pool, { refquota: 10_240, compression: false })

    expect(created).to be_persisted
    expect(tx_classes(chain)).to eq([Transactions::Storage::CreatePool])
    expect(chain.concern_type).to eq('chain_affect')
    expect(chain.transaction_chain_concerns.pluck(:class_name, :row_id)).to include(
      ['Pool', created.id]
    )
    expect(chain.locks.map { |lock| [lock.resource, lock.row_id] }).to include(
      ['Node', SpecSeed.node.id],
      ['Pool', created.id]
    )

    properties = DatasetProperty.where(pool: created).index_by(&:name)
    expect(properties.keys).to match_array(property_registry.keys.map(&:to_s))
    expect(properties.fetch('refquota').value).to eq(10_240)
    expect(properties.fetch('compression').value).to be(false)
    expect(properties.fetch('sync').value).to eq('standard')
    expect(properties.fetch('atime').value).to be(false)
    expect(properties.values).to all(
      have_attributes(
        inherited: false,
        confirmed: :confirm_create
      )
    )
  end
end
