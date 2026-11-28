require 'spec_helper'

RSpec.describe VpsEvidenceDailyTotal do
  include_context 'with accepted VPS evidence fixture'
  let(:now) { Time.utc(2026, 11, 28, 12, 0, 5, 123_456) }
  let(:vps) { build_standalone_vps_fixture(user: SpecSeed.user).fetch(:vps) }

  it 'records newly accepted disjoint pieces once while reporting is disabled' do
    data = accepted_evidence_fixture(vps, observed_at: now)
    expect(described_class.sole.recorded_us).to eq(2_000_000)
    expect(IncidentReport.where(vps:)).to be_empty
    travel_to(now, with_usec: true) { expect(VpsEvidence.ingest!(vps.node, data)).to eq(:duplicate) }
    accepted_evidence_fixture(vps, observed_at: now + Rational(1, 1_000_000), sequence: 43)
    expect(described_class.sole.recorded_us).to eq(2_000_001)
    expect(described_class.sole).to have_attributes(first_accepted_at: now, last_accepted_at: now + Rational(1, 1_000_000))
    expect(described_class.sum(:recorded_us)).to eq(VpsEvidenceInterval.live.where(vps:).sum(:credit_us))
  end

  it 'splits at UTC midnight with exact integer microseconds independent of the local timezone' do
    first = Time.utc(2026, 11, 27, 23, 59, 59, 999_999)
    last = Time.utc(2026, 11, 28, 0, 0, 0, 250_000)
    described_class.record_piece!(vps:, signal: 'rtnl_latency', from_at: first.getlocal('+02:00'), to_at: last, accepted_at: now)
    expect(described_class.order(:day).pluck(:day, :recorded_us)).to eq([[Date.new(2026, 11, 27), 1], [Date.new(2026, 11, 28), 250_000]])
    expect(described_class.sum(:recorded_us)).to eq(250_001)
  end

  it 'keeps genuine null accounting epochs separate from real timestamps and new owners' do
    vps.update_columns(incident_accounting_since: nil)
    described_class.record_piece!(vps:, signal: 'rtnl_latency', from_at: now - 1, to_at: now, accepted_at: now)
    old = described_class.sole
    expect(old.accounting_since).to be_nil
    expect(old.accounting_epoch_key).to eq('-')
    vps.update_columns(user_id: SpecSeed.other_user.id, incident_accounting_since: now)
    described_class.record_piece!(vps:, signal: 'rtnl_latency', from_at: now, to_at: now + 1, accepted_at: now + 1)
    expect(described_class.order(:id).pluck(:accounting_epoch_key)).to eq(['-', now.iso8601(6)])
    expect(old.reload.user_id).to eq(SpecSeed.user.id)
  end

  it 'rolls the daily row back with the original acceptance transaction' do
    allow(VpsEvidence).to receive(:evaluate!).and_raise('report failed')
    expect { accepted_evidence_fixture(vps, observed_at: now) }.to raise_error(RuntimeError, 'report failed')
    expect(described_class.count).to eq(0)
    expect(VpsEvidenceEvent.count).to eq(0)
    expect(VpsEvidenceInterval.count).to eq(0)
  end

  it 'retains exactly the last 32 UTC calendar days without extending raw interval retention' do
    first = Time.utc(2026, 10, 27, 23, 59, 59)
    described_class.record_piece!(vps:, signal: 'rtnl_latency', from_at: first, to_at: first + 2, accepted_at: now)
    accepted_evidence_fixture(vps, observed_at: now)
    VpsEvidence.prune!(now:)
    expect(described_class.order(:day).pluck(:day)).to eq([Date.new(2026, 10, 28), Date.new(2026, 11, 28)])
    VpsEvidence.prune!(now: now + 86_701)
    expect(VpsEvidenceInterval.live.where(vps:)).to be_empty
    expect(described_class.sum(:recorded_us)).to eq(2_000_000)
  end
end
