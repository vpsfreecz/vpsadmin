require 'spec_helper'

RSpec.describe VpsAdmin::API::Resources::VpsEvidence do
  include_context 'with accepted VPS evidence fixture'
  let(:now) { Time.utc(2026, 11, 25, 12, 0, 5, 123_456) }
  let(:vps) { build_standalone_vps_fixture(user: SpecSeed.user).fetch(:vps) }

  before { header 'Accept', 'application/json' }

  def read_as(user, path, **params)
    travel_to(now, with_usec: true) { as(user) { get vpath(path), vps_evidence: params } }
  end

  it 'returns current owner rows, typed metadata and references while hiding administrative identities' do
    accepted_evidence_fixture(vps, observed_at: now)
    foreign = build_standalone_vps_fixture(user: SpecSeed.other_user).fetch(:vps)
    accepted_evidence_fixture(foreign, observed_at: now + Rational(1, 1_000_000), sequence: 43)
    read_as(vps.user, '/vps_evidence', limit: 1)
    expect(last_response.status).to eq(200), last_response.body
    expect(json.dig('response', '_meta')).to include('total_count' => 1, 'next_offset' => nil, 'configuration_valid' => true, 'unavailable_signals' => [], 'read_at' => now.iso8601(6))
    row = json.dig('response', 'vps_evidence').sole
    expect(row).to include('vps' => hash_including('id' => vps.id), 'credit_us' => 2_000_000, 'reporting_enabled' => false, 'report_eligible' => true)
    expect(row).not_to have_key('user')
    expect(row).not_to have_key('node')
    expect(row).not_to have_key('target')
    read_as(SpecSeed.admin, '/vps_evidence', limit: 1)
    expect(json.dig('response', '_meta')).to include('total_count' => 2, 'next_offset' => 1)
    expect(json.dig('response', 'vps_evidence').sole).to have_key('user')
  end

  it 'provides recorded-zero child evidence and denies foreign or unauthenticated reads' do
    read_as(vps.user, "/vpses/#{vps.id}/evidence")
    expect(last_response.status).to eq(200), last_response.body
    expect(json.dig('response', 'evidence').sole).to include('credit_us' => 0, 'observation_state' => 'no_data', 'window_complete' => false)
    read_as(SpecSeed.other_user, "/vpses/#{vps.id}/evidence")
    expect(last_response.status).to eq(404)
    get vpath('/vps_evidence')
    expect(last_response.status).to eq(401)
  end

  it 'keeps invalid configuration arrays distinct from an empty valid fleet and validates paging' do
    SysConfig.where(category: 'vps_evidence_rtnl_latency', name: 'window_seconds').update_all(value: '"invalid"')
    read_as(vps.user, '/vps_evidence')
    expect(last_response.status).to eq(200), last_response.body
    expect(json.dig('response', '_meta')).to include('configuration_valid' => false, 'unavailable_signals' => ['rtnl_latency'])
    expect(json.dig('response', 'vps_evidence')).to eq([])
    read_as(vps.user, '/vps_evidence', limit: 101)
    expect(json['status']).to be(false)
    expect(json.dig('errors', 'limit')).not_to be_nil
  end

  it 'rechecks current authorization in SQL after the parent lookup without reconciling ownership' do
    accepted_evidence_fixture(vps, observed_at: now)
    allow(VpsEvidenceReadProjection).to receive(:new).and_wrap_original do |method, **options|
      vps.update_columns(user_id: SpecSeed.other_user.id, incident_accounting_since: now)
      method.call(**options)
    end
    original = VpsEvidenceState.find_by!(vps:).attributes
    read_as(SpecSeed.user, "/vpses/#{vps.id}/evidence")
    expect(last_response.status).to eq(404)
    expect(VpsEvidenceState.find_by!(vps:).attributes).to eq(original)
  end

  it 'supports intersected placement filters and admin-only owner selection without revealing foreign counts' do
    accepted_evidence_fixture(vps, observed_at: now)
    foreign = build_standalone_vps_fixture(user: SpecSeed.other_user).fetch(:vps)
    accepted_evidence_fixture(foreign, observed_at: now + Rational(1, 1_000_000), sequence: 43)
    filters = { vps: vps.id, node: vps.node_id, location: vps.node.location_id,
                environment: vps.node.location.environment_id, user: vps.user_id }
    read_as(SpecSeed.admin, '/vps_evidence', **filters, limit: 1)
    expect(last_response.status).to eq(200), last_response.body
    expect(json.dig('response', '_meta')).to include('total_count' => 1, 'next_offset' => nil)
    expect(json.dig('response', 'vps_evidence').sole.dig('vps', 'id')).to eq(vps.id)
    read_as(SpecSeed.other_user, '/vps_evidence', **filters.except(:user))
    expect(json.dig('response', '_meta', 'total_count')).to eq(0)
    expect(json.dig('response', 'vps_evidence')).to eq([])
    read_as(vps.user, '/vps_evidence', user: foreign.user_id)
    # HaveAPI omits blacklisted inputs, as on VPS Index; they cannot widen scope.
    expect(json['status']).to be(true)
    expect(json.dig('response', '_meta', 'total_count')).to eq(1)
    expect(json.dig('response', 'vps_evidence').map { |row| row.dig('vps', 'id') }).to eq([vps.id])
    expect(json.dig('response', 'vps_evidence').sole).not_to have_key('user')
    read_as(vps.user, '/vps_evidence', node: 99_999_999)
    expect(json['status']).to be(false)
  end
end
