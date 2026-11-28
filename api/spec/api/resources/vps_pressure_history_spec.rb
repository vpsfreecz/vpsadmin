require 'spec_helper'

RSpec.describe VpsAdmin::API::Resources::VpsPressureHistory do
  let(:now) { Time.utc(2026, 11, 28, 12, 0, 5, 123_456) }
  let(:vps) { build_standalone_vps_fixture(user: SpecSeed.user).fetch(:vps) }

  before { header 'Accept', 'application/json' }

  def read_as(user, **params)
    travel_to(now, with_usec: true) { as(user) { get vpath('/vps_pressure_history'), vps_pressure_history: { vps: vps.id, **params } } }
  end

  it 'serializes exact daily values, UTC bounds, nullable metadata and 7/30 calendar choices' do
    VpsEvidenceDailyTotal.record_piece!(vps:, signal: 'rtnl_latency', from_at: now - 1, to_at: now, accepted_at: now)
    read_as(vps.user)
    expect(last_response.status).to eq(200), last_response.body
    rows = json.dig('response', 'vps_pressure_history')
    expect(rows.length).to eq(7)
    expect(rows.first).to include('recorded_us' => nil, 'partial_day' => false)
    expect(rows.last).to include('recorded_us' => 1_000_000, 'partial_day' => true, 'to_at' => '2026-11-29T00:00:00.000000Z')
    expect(json.dig('response', '_meta')).to include('read_at' => now.iso8601(6), 'timezone' => 'UTC', 'available' => true,
                                                     'total_recorded_us' => 1_000_000, 'first_recorded_at' => now.iso8601(6))
    read_as(SpecSeed.admin, days: 30)
    expect(json.dig('response', 'vps_pressure_history').length).to eq(30)
    read_as(vps.user, days: 8)
    expect(json['status']).to be(false)
  end

  it 'denies foreign and unauthenticated reads rather than returning foreign unavailable metadata' do
    read_as(SpecSeed.other_user)
    expect(last_response.status).to eq(404)
    get vpath('/vps_pressure_history'), vps_pressure_history: { vps: vps.id }
    expect(last_response.status).to eq(401)
  end
end
