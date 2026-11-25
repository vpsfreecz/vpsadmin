require 'spec_helper'

RSpec.describe VpsAdmin::API::DailyReportVpsEvidence do
  include_context 'with accepted VPS evidence fixture'
  let(:now) { Time.utc(2026, 11, 25, 12, 0, 5, 123_456) }
  let(:vps) { build_standalone_vps_fixture.fetch(:vps) }

  it 'materializes actual accepted gains once with exact times, original owner and safe current links' do
    data = accepted_evidence_fixture(vps, observed_at: now - 5, accepted_at: now)
    live = VpsEvidenceInterval.live.where(vps:).sole
    expect(live.accepted_at).to eq(now)
    expect(live.to_at).to eq(now - 7)
    travel_to(now + 1, with_usec: true) { expect(VpsEvidence.ingest!(vps.node, data)).to eq(:duplicate) }
    vars = described_class.new(from: now - 1, to: now, base_url: 'https://admin.example.test/').vars
    expect(vars).to include(from: now - 1, to: now, generated_at: now)
    expect(vars[:by_signal].sole).to include(signal: 'rtnl_latency', accepted_us: 2_000_000, row_count: 1)
    expect(vars[:rows].sole).to include(vps_id: vps.id, user_id: vps.user_id, accounting_since: nil, accepted_us: 2_000_000,
                                        first_accepted_at: now, last_accepted_at: now, vps_url: "https://admin.example.test/?page=adminvps&action=info&veid=#{vps.id}")
    expect(described_class.new(from: now, to: now + 1).vars[:rows]).to be_empty
    expect(described_class.new(from: now - 1, to: now, base_url: 'https://secret@example.test/').vars[:rows].sole[:vps_url]).to be_nil
  end

  it 'retains accepted rows for the daily period even when their short rolling window expires' do
    accepted_evidence_fixture(vps, observed_at: now)
    SysConfig.find_by!(category: 'vps_evidence_rtnl_latency', name: 'threshold_seconds').update!(value: 2)
    SysConfig.find_by!(category: 'vps_evidence_rtnl_latency', name: 'window_seconds').update!(value: 60)
    VpsEvidence.prune!(now: now + 120)
    expect(VpsEvidenceInterval.live.where(vps:).count).to eq(1)
    expect(described_class.new(from: now - 1, to: now + 120).vars[:rows].sole[:accepted_us]).to eq(2_000_000)
    VpsEvidence.prune!(now: now + 86_701)
    expect(VpsEvidenceInterval.live.where(vps:)).to be_empty
  end

  it 'counts only new overlap-free live pieces and keeps owner epochs separate from copies and repeats' do
    accepted_evidence_fixture(vps, observed_at: now)
    first = VpsEvidenceInterval.live.where(vps:).sole
    accepted_evidence_fixture(vps, observed_at: now + 1, sequence: 43)
    late_period = described_class.new(from: now, to: now + 1).vars
    expect(late_period[:rows].sole[:accepted_us]).to eq(1_000_000)
    expect(first.reload.accepted_at).to eq(now)
    expect { first.update_columns(accepted_at: now + 2) }.to raise_error(ActiveRecord::ActiveRecordError)
    report = IncidentReport.create!(vps:, user: vps.user, subject: 'Saved fixture', text: 'Immutable intervals', detected_at: now)
    VpsEvidenceInterval.create!(first.attributes.except('id', 'accepted_at').merge(incident_report: report))
    expect(report.vps_evidence_intervals.sole.accepted_at).to be_nil
    old_user = vps.user_id
    vps.update_columns(user_id: SpecSeed.other_user.id, incident_accounting_since: now + 2)
    vps.reload
    accepted_evidence_fixture(vps, observed_at: now + 6, sequence: 44)
    rows = described_class.new(from: now - 1, to: now + 7).vars[:rows]
    expect(rows.map { |row| [row[:user_id], row[:accounting_since], row[:accepted_us]] }).to contain_exactly(
      [old_user, nil, 3_000_000], [SpecSeed.other_user.id, now + 2, 2_000_000]
    )
  end
end
