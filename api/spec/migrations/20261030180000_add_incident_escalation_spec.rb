require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20261030180000_add_incident_escalation')

RSpec.describe AddIncidentEscalation do
  before do
    define_schema do
      create_table(:vpses) { |t| t.string :hostname }
      create_table(:incident_reports) do |t|
        t.string :codename
        t.bigint :vps_id
        t.bigint :user_id
        t.datetime :detected_at
      end
    end
  end

  it 'keeps legacy incidents unqualified and enables inherited VPS settings' do
    insert_row(:vpses, hostname: 'old')
    insert_row(:incident_reports, vps_id: 1, user_id: 1, detected_at: Time.now)
    migrate_up!
    expect(rows(:vpses).first).to include('incident_enforcement_enabled' => 1)
    expect(rows(:vps_incident_policies)).to be_empty
    expect(rows(:incident_reports).first['source_key']).to be_nil
    expect(rows(:incident_reports).first['notification_processed_at']).to be_nil
    expect(column(:incident_reports, :notification_processed_at).null).to be(true)
    insert_row(:incident_reports, source_key: 'source')
    expect { insert_row(:incident_reports, source_key: 'source') }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'removes only feature schema on rollback' do
    insert_row(:vpses, hostname: 'preserved')
    migrate_up!
    migrate_down!
    expect(column_exists?(:vpses, :incident_accounting_since)).to be(false)
    expect(column_exists?(:incident_reports, :notification_processed_at)).to be(false)
    expect(connection.table_exists?(:vps_incident_actions)).to be(false)
    expect(rows(:vpses).first['hostname']).to eq('preserved')
  end
end
