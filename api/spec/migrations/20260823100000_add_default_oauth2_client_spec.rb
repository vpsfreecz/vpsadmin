# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260823100000_add_default_oauth2_client')

RSpec.describe AddDefaultOauth2Client do
  before do
    define_schema do
      create_table :oauth2_clients
    end
  end

  it 'adds a nullable default flag with a unique index' do
    migrate_up!

    expect(column(:oauth2_clients, :is_default)).to have_attributes(
      type: :boolean,
      null: true,
      default: nil
    )
    index = connection.indexes(:oauth2_clients).find do |candidate|
      candidate.name == 'index_oauth2_clients_on_is_default'
    end
    expect(index.unique).to be(true)

    insert_row(:oauth2_clients, is_default: nil)
    insert_row(:oauth2_clients, is_default: nil)
    insert_row(:oauth2_clients, is_default: true)
    expect do
      insert_row(:oauth2_clients, is_default: true)
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'removes the default flag on rollback' do
    migrate_up!

    migrate_down!

    expect(column_exists?(:oauth2_clients, :is_default)).to be(false)
  end
end
