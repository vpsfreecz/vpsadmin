require 'spec_helper'

RSpec.describe VpsPressureHistoryProjection do
  let(:now) { Time.utc(2026, 11, 28, 12, 0, 5, 123_456) }
  let(:vps) { build_standalone_vps_fixture(user: SpecSeed.user).fetch(:vps) }

  def read(user: vps.user, at: now, days: 7)
    described_class.new(user:, now: at).for_vps(vps.id, days:)
  end

  def record(at, duration = 250_001, accepted_at: now)
    VpsEvidenceDailyTotal.record_piece!(vps:, signal: 'rtnl_latency', from_at: at,
                                        to_at: at + Rational(duration, 1_000_000), accepted_at:)
  end

  it 'returns fixed calendar bounds and unknown bins without inferring measured zero' do
    result = read
    expect(result[:rows].length).to eq(7)
    expect(result[:rows].first).to include(id: '2026-11-22', from_at: Time.utc(2026, 11, 22), to_at: Time.utc(2026, 11, 23), recorded_us: nil, partial_day: false)
    expect(result[:rows].last).to include(to_at: Time.utc(2026, 11, 29), partial_day: true)
    expect(result[:meta]).to include(available: true, timezone: 'UTC', read_at: now,
                                     range_to: Time.utc(2026, 11, 29), total_recorded_us: nil, first_recorded_at: nil)
    expect { read(days: 8) }.to raise_error(ArgumentError)
  end

  it 'preserves accepted subsecond and future-tolerance pieces without clipping to the read instant' do
    record(now - 1)
    record(now + 1, 1)
    result = read
    expect(result[:rows].last[:recorded_us]).to eq(250_002)
    expect(result[:meta]).to include(total_recorded_us: 250_002, first_recorded_at: now)
  end

  it 'scopes first retained acceptance independently of requested days and excludes expired and next-day rows' do
    record(Time.utc(2026, 10, 27), 1, accepted_at: now - 100)
    record(Time.utc(2026, 10, 28), 1, accepted_at: now - 50)
    record(Time.utc(2026, 11, 29), 1, accepted_at: now - 200)
    expect(read[:meta]).to include(total_recorded_us: nil, first_recorded_at: now - 50)
    record(now, 1)
    expect(read(days: 30)[:meta]).to include(total_recorded_us: 1, first_recorded_at: now - 50)
  end

  it 'protects original user and exact null or nonnull epoch even for administrators' do
    vps.update_columns(incident_accounting_since: nil)
    record(now, 120_000_000)
    expect(read[:meta]).to include(accounting_since: nil, ownership_limited: false, total_recorded_us: 120_000_000)
    old_user = vps.user
    vps.update_columns(user_id: SpecSeed.other_user.id, incident_accounting_since: now - 1)
    expect { read(user: old_user) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(read(user: SpecSeed.admin)[:meta]).to include(total_recorded_us: nil, ownership_limited: true, accounting_since: now - 1)
    record(now, 1)
    expect(read(user: SpecSeed.other_user)[:meta][:total_recorded_us]).to eq(1)
  end

  it 'makes pending and known mismatched states unavailable without using current settings or freshness' do
    record(now, 45_000_000)
    vps.update_columns(incident_owner_transfer_chain_id: 123)
    result = read
    expect(result[:meta]).to include(available: false, total_recorded_us: nil, first_recorded_at: nil)
    expect(result[:rows].pluck(:recorded_us)).to all(be_nil)
    vps.update_columns(incident_owner_transfer_chain_id: nil)
    VpsEvidenceState.create!(vps:, signal: 'rtnl_latency', user: SpecSeed.other_user, accounting_since: now)
    expect(read[:meta][:available]).to be(false)
    VpsEvidenceState.where(vps:).delete_all
    SysConfig.where(category: 'vps_evidence_rtnl_latency', name: 'window_seconds').update_all(value: '"invalid"')
    expect(read[:meta]).to include(available: true, total_recorded_us: 45_000_000)
  end

  it 'uses one SQL snapshot and UTC days across a local daylight-saving transition' do
    at = Time.utc(2026, 10, 25, 1, 30)
    record(Time.utc(2026, 10, 24, 23, 59, 59, 999_999), 2)
    reader = described_class.new(user: vps.user, now: at.getlocal('+01:00'))
    queries = []
    result = nil
    callback = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] unless payload[:name] == 'SCHEMA' }
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { result = reader.for_vps(vps.id, days: 30) }
    expect(queries.length).to eq(1)
    expect(result[:rows].last(2).pluck(:id, :recorded_us)).to eq([['2026-10-24', 1], ['2026-10-25', 1]])
    expect(result[:rows].last[:to_at]).to eq(Time.utc(2026, 10, 26))
  end
end
