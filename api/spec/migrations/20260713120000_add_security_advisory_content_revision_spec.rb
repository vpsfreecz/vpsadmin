# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260713120000_add_security_advisory_content_revision')

RSpec.describe AddSecurityAdvisoryContentRevision do
  before do
    define_schema do
      create_table :security_advisories do |t|
        t.string :name
        t.timestamps
      end
    end
  end

  it 'adds a non-null revision initialized to zero' do
    advisory_id = insert_row(
      :security_advisories,
      name: 'Draft',
      created_at: timestamp,
      updated_at: timestamp
    )

    migrate_up!

    revision = column(:security_advisories, :content_revision)
    expect(revision.null).to be(false)
    expect(revision.default.to_i).to eq(0)
    expect(find_row(:security_advisories, id: advisory_id).fetch('content_revision').to_i).to eq(0)
  end

  it 'removes the revision on rollback' do
    migrate_up!

    migrate_down!

    expect(column_exists?(:security_advisories, :content_revision)).to be(false)
  end
end
