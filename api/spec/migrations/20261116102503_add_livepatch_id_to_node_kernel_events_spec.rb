# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20261116102503_add_livepatch_id_to_node_kernel_events')

RSpec.describe AddLivepatchIdToNodeKernelEvents do
  before do
    define_schema do
      create_table :node_kernel_events do |t|
        t.string :reported_release, null: false
      end
    end
    connection.execute(<<~SQL.squish)
      INSERT INTO node_kernel_events (reported_release) VALUES ('6.12.113')
    SQL
  end

  it 'adds a nullable bounded ID without a default or backfill and rolls back' do
    migrate_up!

    livepatch_id = column(:node_kernel_events, :livepatch_id)
    expect(livepatch_id.null).to be(true)
    expect(livepatch_id.limit).to eq(63)
    expect(livepatch_id.default).to be_nil
    expect(connection.select_value('SELECT livepatch_id FROM node_kernel_events')).to be_nil
    expect(connection.select_value('SELECT reported_release FROM node_kernel_events'))
      .to eq('6.12.113')

    migrate_down!
    expect(column_exists?(:node_kernel_events, :livepatch_id)).to be(false)
    expect(connection.select_value('SELECT COUNT(*) FROM node_kernel_events')).to eq(1)
  end
end
