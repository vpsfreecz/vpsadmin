require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20261006120000_add_network_enabled')

RSpec.describe AddNetworkEnabled do
  before do
    define_schema do
      create_table(:networks) { |t| t.string :address }
    end
  end

  it 'enables existing and new networks by default and persists false' do
    existing = insert_row(:networks, address: '192.0.2.0')
    migrate_up!
    expect(column(:networks, :enabled).null).to be(false)
    expect(rows(:networks).first['enabled']).to eq(1)
    insert_row(:networks, address: '198.51.100.0')
    connection.execute("UPDATE networks SET enabled = 0 WHERE id = #{existing}")
    expect(rows(:networks).map { |row| row['enabled'] }).to eq([0, 1])
  end

  it 'removes only the availability column on schema rollback' do
    insert_row(:networks, address: '192.0.2.0')
    migrate_up!
    migrate_down!
    expect(column_exists?(:networks, :enabled)).to be(false)
    expect(rows(:networks).first['address']).to eq('192.0.2.0')
  end
end
