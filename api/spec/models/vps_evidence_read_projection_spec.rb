require 'spec_helper'

RSpec.describe VpsEvidenceReadProjection do
  include_context 'with accepted VPS evidence fixture'
  let(:now) { Time.utc(2026, 11, 25, 12, 0, 5, 123_456) }
  let(:vps) { build_standalone_vps_fixture(user: SpecSeed.user).fetch(:vps) }

  def projection(user = vps.user, at: now)
    described_class.new(user:, now: at)
  end

  it 'reads the real accepted ledger without changing state and matches ordinary clipping' do
    accepted_evidence_fixture(vps, observed_at: now)
    state = VpsEvidenceState.find_by!(vps:, signal: 'rtnl_latency')
    before = [VpsEvidenceEvent.count, VpsEvidenceInterval.count, state.attributes, IncidentReport.count]
    result = projection.positive
    expect(result[:meta]).to include(total_count: 1, read_at: now, configuration_valid: true, unavailable_signals: [])
    row = result[:rows].sole
    expect(row).to include(credit_us: 2_000_000, observation_state: 'fresh', qualification: 'qualified',
                           report_eligible: true, report_due: false, reporting_enabled: false, window_complete: false,
                           measurement: 'rtnl_latency', peak_unit: 'microseconds', peak_value: 3_000_000, peak_is_lower_bound: false)
    settings = VpsEvidence.config('rtnl_latency')
    expect(row[:credit_us]).to eq(VpsEvidence.projection(vps, state, now:, settings:)[:credit_us])
    expect([VpsEvidenceEvent.count, VpsEvidenceInterval.count, state.reload.attributes, IncidentReport.count]).to eq(before)
  end

  it 'authorizes current owners before counts and pages and includes recorded-zero child rows' do
    accepted_evidence_fixture(vps, observed_at: now)
    other = build_standalone_vps_fixture(user: SpecSeed.other_user).fetch(:vps)
    accepted_evidence_fixture(other, observed_at: now + Rational(1, 1_000_000), sequence: 43)
    expect(projection.positive[:meta][:total_count]).to eq(1)
    expect(projection.positive(offset: 1, limit: 1)[:rows]).to be_empty
    expect(projection(SpecSeed.admin).positive(limit: 1)[:meta]).to include(total_count: 2, next_offset: 1)
    expect { projection.for_vps(other.id) }.to raise_error(ActiveRecord::RecordNotFound)
    empty = build_standalone_vps_fixture(user: SpecSeed.user).fetch(:vps)
    expect(projection.for_vps(empty.id)[:rows].sole).to include(credit_us: 0, observation_state: 'no_data', qualification: nil, report_eligible: false)
  end

  it 'keeps stale same-owner credit visible and preserves positive subsecond clipping exactly' do
    accepted_evidence_fixture(vps, observed_at: now)
    expect(projection(at: now + 31).positive[:rows].sole).to include(credit_us: 2_000_000, observation_state: 'stale', report_eligible: false)
    SysConfig.find_by!(category: 'vps_evidence_rtnl_latency', name: 'threshold_seconds').update!(value: 2)
    SysConfig.find_by!(category: 'vps_evidence_rtnl_latency', name: 'window_seconds').update!(value: 60)
    row = projection(at: now + Rational(57_000_001, 1_000_000)).positive[:rows].sole
    expect(row[:credit_us]).to eq(999_999)
    expect(row[:window_from].usec).to eq(123_457)
  end

  it 'returns unavailable configuration metadata rather than an apparently complete empty fleet' do
    accepted_evidence_fixture(vps, observed_at: now)
    SysConfig.where(category: 'vps_evidence_rtnl_latency', name: 'window_seconds').update_all(value: '"invalid"')
    expect(projection.positive).to include(rows: [], meta: hash_including(configuration_valid: false, unavailable_signals: ['rtnl_latency']))
    row = projection.for_vps(vps.id)[:rows].sole
    expect(row).to include(configuration_valid: false, credit_us: nil, window_from: nil, threshold_seconds: nil, report_due: nil)
  end

  it 'hides pending and previous-owner proof while preserving same-owner credit across node changes' do
    accepted_evidence_fixture(vps, observed_at: now)
    vps.update_columns(node_id: SpecSeed.other_node.id)
    expect(projection.for_vps(vps.id)[:rows].sole).to include(credit_us: 2_000_000, report_eligible: false)
    vps.update_columns(incident_owner_transfer_chain_id: 123)
    expect(projection.for_vps(vps.id)[:rows].sole).to include(credit_us: nil, observation_state: 'no_data', last_observed_at: nil,
                                                              last_incident_at: nil, qualification: nil, measurement: nil, report_eligible: false, window_complete: false)
    expect(projection.positive[:rows]).to be_empty
    vps.update_columns(incident_owner_transfer_chain_id: nil, user_id: SpecSeed.other_user.id, incident_accounting_since: now)
    expect(projection(SpecSeed.other_user).for_vps(vps.id)[:rows].sole).to include(credit_us: nil, last_observed_at: nil)
    expect(projection(SpecSeed.other_user).positive[:rows]).to be_empty
    expect { projection(SpecSeed.user).for_vps(vps.id) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'gets fleet count, page and current mutable facts in one query after configuration selection' do
    accepted_evidence_fixture(vps, observed_at: now)
    reader = projection
    queries = []
    callback = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] unless payload[:name] == 'SCHEMA' }
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
      expect(reader.positive(limit: 1)[:rows].length).to eq(1)
    end
    expect(queries.length).to eq(1)
    expect(queries.sole).to include('COUNT(*)', 'vps_evidence_states', 'vps_current_statuses', 'LIMIT 1')
  end

  it 'intersects placement and owner filters before totals and offset pagination' do
    accepted_evidence_fixture(vps, observed_at: now)
    other = build_standalone_vps_fixture(user: SpecSeed.other_user).fetch(:vps)
    accepted_evidence_fixture(other, observed_at: now + Rational(1, 1_000_000), sequence: 43)
    filters = { user_id: vps.user_id, node_id: vps.node_id, location_id: vps.node.location_id,
                environment_id: vps.node.location.environment_id, signal: 'rtnl_latency' }
    result = projection(SpecSeed.admin).positive(**filters, limit: 1)
    expect(result[:rows].sole[:vps_id]).to eq(vps.id)
    expect(result[:meta]).to include(total_count: 1, next_offset: nil)
    expect(projection(SpecSeed.admin).positive(**filters, offset: 1)[:rows]).to be_empty
    expect(projection.positive(user_id: other.user_id)[:meta][:total_count]).to eq(0)
    expect(projection.positive(node_id: -1)[:meta][:total_count]).to eq(0)
    expect(projection.positive(location_id: -1)[:rows]).to be_empty
    expect(projection.positive(environment_id: -1)[:rows]).to be_empty
  end
end
