require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20261128100000_add_vps_evidence_daily_totals')

RSpec.describe AddVpsEvidenceDailyTotals do
  before do
    # The final core schema differs from the consumed predecessor only by this
    # additive table/version. Removing this table establishes that predecessor.
    load File.expand_path('../../db/schema.rb', __dir__)
    migrate_down!
    insert_row(:vps_evidence_intervals, vps_id: 1, user_id: 2, signal: 'rtnl_latency',
                                        from_at: timestamp - 1, to_at: timestamp, credit_us: 1_000_000,
                                        accepted_at: timestamp, evidence: '{}')
  end

  it 'adds a uniquely indexed daily identity while preserving consumed evidence data' do
    old = rows(:vps_evidence_intervals)
    migrate_up!
    expect(rows(:vps_evidence_intervals)).to eq(old)
    expect(rows(:vps_evidence_daily_totals)).to be_empty
    expect(column(:vps_evidence_daily_totals, :accounting_since).null).to be(true)
    expect(column(:vps_evidence_daily_totals, :accounting_since).precision).to eq(6)
    attrs = { day: timestamp.to_date, vps_id: 1, user_id: 2, signal: 'rtnl_latency', accounting_epoch_key: '-',
              recorded_us: 1, first_accepted_at: timestamp, last_accepted_at: timestamp }
    insert_row(:vps_evidence_daily_totals, attrs)
    expect { insert_row(:vps_evidence_daily_totals, attrs) }.to raise_error(ActiveRecord::RecordNotUnique)
    insert_row(:vps_evidence_daily_totals, attrs.merge(accounting_since: timestamp, accounting_epoch_key: timestamp.iso8601(6)))
    insert_row(:vps_evidence_daily_totals, attrs.merge(user_id: 3))
    expect(row_count(:vps_evidence_daily_totals)).to eq(3)
    migrate_down! # Explicit disposable development rollback only.
    expect(rows(:vps_evidence_intervals)).to eq(old)
    expect(table_exists?(:vps_evidence_daily_totals)).to be(false)
  end
end
