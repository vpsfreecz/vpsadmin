require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20261125120000_add_vps_evidence')

RSpec.describe AddVpsEvidence do
  before do
    define_schema do
      create_table(:incident_reports) { |t| t.text :text }
    end
  end

  it 'adds a unique receipt identity without qualifying old reports' do
    insert_row(:incident_reports, text: 'legacy')
    migrate_up!
    expect(rows(:incident_reports).sole['evidence_snapshot']).to be_nil
    accepted = ActiveRecord::Base.connection.columns(:vps_evidence_intervals).find { |column| column.name == 'accepted_at' }
    expect(accepted.precision).to eq(6)
    expect(accepted.null).to be(true) # Immutable incident copies have no acceptance timestamp.
    expect(ActiveRecord::Base.connection.indexes(:vps_evidence_intervals).map(&:columns)).to include(%w[incident_report_id accepted_at])
    attrs = { node_id: 1, signal: 'rtnl_latency', producer_epoch: 'a' * 32, sequence: 1, part: 1, parts: 1, digest: 'd' * 64,
              observed_at: Time.now.utc, received_at: Time.now.utc, facts: '{}' }
    insert_row(:vps_evidence_events, attrs)
    expect(rows(:vps_evidence_events).sole['current_stream']).to eq(0)
    expect { insert_row(:vps_evidence_events, attrs) }.to raise_error(ActiveRecord::RecordNotUnique)
    insert_row(:vps_evidence_events, attrs.merge(signal: 'second_test_signal'))
    expect(rows(:vps_evidence_events).length).to eq(2)
  end

  it 'removes only the new schema when explicitly rolled back' do
    insert_row(:incident_reports, text: 'legacy')
    migrate_up!
    migrate_down!
    expect(table_exists?(:vps_evidence_intervals)).to be(false)
    expect(column_exists?(:incident_reports, :evidence_snapshot)).to be(false)
    expect(rows(:incident_reports).sole['text']).to eq('legacy')
  end
end
