# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260806120000_add_node_kernel_livepatch_actions')

RSpec.describe AddNodeKernelLivepatchActions do
  before do
    define_schema do
      create_table :node_kernel_events do |t|
        t.integer :event_type, null: false
      end
    end
  end

  it 'adds a nullable lifecycle action and removes it on rollback' do
    migrate_up!

    expect(column_exists?(:node_kernel_events, :livepatch_action)).to be(true)
    expect(column(:node_kernel_events, :livepatch_action).null).to be(true)

    migrate_down!
    expect(column_exists?(:node_kernel_events, :livepatch_action)).to be(false)
  end
end
