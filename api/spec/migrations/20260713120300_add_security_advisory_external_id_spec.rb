# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260713120300_add_security_advisory_external_id')

RSpec.describe AddSecurityAdvisoryExternalId do
  before do
    define_schema do
      create_table :security_advisories do |t|
        t.string :name
        t.timestamps
      end
    end
  end

  it 'adds an optional uniquely indexed idempotency key' do
    advisory_id = insert_row(
      :security_advisories,
      name: 'Existing draft',
      created_at: timestamp,
      updated_at: timestamp
    )

    migrate_up!

    external_id = column(:security_advisories, :external_id)
    expect(external_id.null).to be(true)
    expect(external_id.limit).to eq(255)
    external_id_index = connection.indexes(:security_advisories).find do |index|
      index.columns == ['external_id']
    end
    expect(external_id_index).not_to be_nil
    expect(external_id_index.unique).to be(true)
    expect(find_row(:security_advisories, id: advisory_id).fetch('external_id')).to be_nil
  end

  it 'removes the idempotency key on rollback' do
    migrate_up!

    migrate_down!

    expect(column_exists?(:security_advisories, :external_id)).to be(false)
  end
end
