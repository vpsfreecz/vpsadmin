# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260818115900_add_authentication_generation')

RSpec.describe AddAuthenticationGeneration do
  before do
    define_schema do
      create_table :users
    end
  end

  it 'adds a generation counter used to serialize authentication' do
    migrate_up!

    expect(column(:users, :authentication_generation)).to have_attributes(
      type: :integer,
      null: false,
      default: 0
    )
  end

  it 'removes the generation counter on rollback' do
    migrate_up!

    migrate_down!

    expect(column_exists?(:users, :authentication_generation)).to be(false)
  end
end
