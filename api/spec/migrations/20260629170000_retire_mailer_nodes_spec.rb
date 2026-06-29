# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260629170000_retire_mailer_nodes')

RSpec.describe RetireMailerNodes do
  def define_nodes_schema
    define_schema do
      create_table :nodes do |t|
        t.string :name, null: false
        t.integer :role, null: false
        t.boolean :active, null: false, default: true
      end
    end
  end

  it 'deactivates mailer nodes and keeps normal nodes active' do
    define_nodes_schema
    node_id = insert_row(:nodes, name: 'node1', role: 0, active: true)
    mailer_id = insert_row(:nodes, name: 'vpsadmin-mailer', role: 2, active: true)
    inactive_mailer_id = insert_row(:nodes, name: 'old-mailer', role: 2, active: false)

    migrate_up!

    expect(boolish(find_row(:nodes, id: node_id).fetch('active'))).to be(true)
    expect(boolish(find_row(:nodes, id: mailer_id).fetch('active'))).to be(false)
    expect(boolish(find_row(:nodes, id: inactive_mailer_id).fetch('active'))).to be(false)
  end

  it 'does not reactivate mailer nodes on rollback' do
    define_nodes_schema
    mailer_id = insert_row(:nodes, name: 'vpsadmin-mailer', role: 2, active: true)
    migrate_up!

    migrate_down!

    expect(boolish(find_row(:nodes, id: mailer_id).fetch('active'))).to be(false)
  end
end
