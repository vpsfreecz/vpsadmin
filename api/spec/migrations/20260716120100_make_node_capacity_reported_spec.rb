# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260716120100_make_node_capacity_reported')

RSpec.describe MakeNodeCapacityReported do
  before do
    define_schema do
      create_table :nodes do |t|
        t.integer :cpus, null: false
        t.integer :total_memory, null: false
        t.integer :total_swap, null: false
      end
    end
  end

  it 'defaults the legacy rollback cache for capacity-optional registration' do
    migrate_up!

    expect(column(:nodes, :cpus).default).to eq(0)
    expect(column(:nodes, :total_memory).default).to eq(0)
    expect(column(:nodes, :total_swap).default).to eq(0)
  end

  it 'removes the cache defaults on rollback' do
    migrate_up!
    migrate_down!

    expect(column(:nodes, :cpus).default).to be_nil
    expect(column(:nodes, :total_memory).default).to be_nil
    expect(column(:nodes, :total_swap).default).to be_nil
  end
end
