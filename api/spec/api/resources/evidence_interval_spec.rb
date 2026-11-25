RSpec.describe VpsAdmin::API::Resources::IncidentReport::EvidenceInterval do
  let(:vps) { build_standalone_vps_fixture.fetch(:vps) }
  let(:snapshot) do
    { 'schema' => 1, 'signal' => 'rtnl_latency', 'representation' => 'qualified_duration', 'enabled' => true, 'window_seconds' => 86_400, 'threshold_seconds' => 300, 'repeat_seconds' => 86_400, 'freshness_seconds' => 30,
      'condition' => { 'measurement' => 'rtnl_latency', 'operator' => 'gt', 'value' => 1_000_000, 'unit' => 'microseconds' }, 'credit_us' => 300_000_000, 'evaluated_at' => Time.now.utc.iso8601(6),
      'window_from' => (Time.now.utc - 86_400).iso8601(6), 'window_to' => Time.now.utc.iso8601(6),
      'window_complete' => false, 'interval_count' => 2, 'qualification_interval_us' => 5_000_000 }
  end
  let(:measurement) do
    { measurement: 'rtnl_latency', peak_unit: 'microseconds', peak_value: 2_000_000, peak_is_lower_bound: false }
  end
  let!(:incident) do
    IncidentReport.create!(vps:, user: vps.user, codename: 'rtnl_latency', source_kind: 'node_oomd_evidence',
                           subject: 'RTNL', text: 'saved', detected_at: Time.now.utc, evidence_snapshot: snapshot)
  end

  before do
    header 'Accept', 'application/json'
    2.times do |index|
      VpsEvidenceInterval.create!(vps:, signal: 'rtnl_latency', user: vps.user, incident_report: incident,
                                  from_at: Time.now.utc.change(usec: 1) - (5 - index), to_at: Time.now.utc.change(usec: 1) - (4 - index), credit_us: 1_000_000,
                                  **measurement.merge(peak_is_lower_bound: measurement[:peak_is_lower_bound].nil? ? nil : index == 0), evidence: {})
    end
  end

  def expect_status(code)
    expect(last_response.status).to eq(code), "#{last_request.path}: #{last_response.body}"
  end

  def read_intervals(user, **params)
    as(user) { get vpath("/incident_reports/#{incident.id}/evidence_intervals"), evidence_interval: params }
  end

  it 'paginates immutable intervals through the authorized parent with saved actual config and counts' do
    read_intervals(vps.user, limit: 1)
    expect_status(200)
    expect(json.dig('response', '_meta')).to include('total_count' => 2, 'next_offset' => 1, 'window_complete' => false, 'threshold_seconds' => 300)
    expect(json.dig('response', 'evidence_intervals').length).to eq(1)
    expect(json.dig('response', 'evidence_intervals', 0)).to include('credit_us' => 1_000_000, 'peak_is_lower_bound' => true)
    expect(json.dig('response', 'evidence_intervals', 0, 'from_at')).to include('.000001')
    read_intervals(vps.user, offset: 1, limit: 1)
    expect_status(200)
    expect(json.dig('response', '_meta', 'next_offset')).to be_nil
    expect(json.dig('response', 'evidence_intervals', 0, 'peak_is_lower_bound')).to be(false)
  end

  it 'rejects another member and anonymous access before reading intervals' do
    read_intervals(SpecSeed.other_user)
    expect_status(404)
    get vpath("/incident_reports/#{incident.id}/evidence_intervals")
    expect_status(401)
  end

  it 'does not expose a prior accounting epoch even when ownership returns to the same user' do
    vps.update_column(:incident_accounting_since, Time.now.utc + 1)
    read_intervals(vps.user)
    expect_status(404)
    read_intervals(SpecSeed.admin)
    expect_status(200)
  end

  it 'bounds pagination and preserves the saved snapshot after live settings change' do
    read_intervals(vps.user, limit: 101)
    expect_status(200) # Existing HaveAPI validation envelope
    expect(json['status']).to be(false)
    expect(json.dig('errors', 'limit')).not_to be_nil
    allow(VpsEvidence).to receive(:config).and_return(VpsAdmin::API::Evidence::RtnlLatency::DEFAULTS.merge(threshold_seconds: 10))
    read_intervals(vps.user)
    expect_status(200)
    expect(json.dig('response', '_meta', 'threshold_seconds')).to eq(300)
  end

  context 'with an interval without a measurement' do
    let(:measurement) { { measurement: nil, peak_unit: nil, peak_value: nil, peak_is_lower_bound: nil } }

    it 'returns nullable typed measurements and saved condition fields without raw source JSON' do
      read_intervals(vps.user, limit: 1)
      expect_status(200)
      expect(json.dig('response', 'evidence_intervals', 0)).to include('measurement' => nil, 'peak_unit' => nil, 'peak_value' => nil, 'peak_is_lower_bound' => nil)
      expect(json.dig('response', '_meta')).to include('signal' => 'rtnl_latency', 'representation' => 'qualified_duration',
                                                       'condition_measurement' => 'rtnl_latency', 'condition_operator' => 'gt', 'condition_value' => 1_000_000, 'condition_unit' => 'microseconds')
      expect(json.dig('response', 'evidence_intervals', 0)).not_to have_key('evidence')
    end
  end

  it 'returns unavailable null evidence metadata for an ordinary report' do
    ordinary = IncidentReport.create!(vps:, user: vps.user, subject: 'Ordinary fixture', text: 'No evidence', detected_at: Time.now.utc)
    as(vps.user) { get vpath("/incident_reports/#{ordinary.id}/evidence_intervals") }
    expect_status(200)
    expect(json.dig('response', 'evidence_intervals')).to eq([])
    expect(json.dig('response', '_meta')).to include('available' => false, 'total_count' => 0, 'next_offset' => nil,
                                                     'signal' => nil, 'representation' => nil, 'condition_measurement' => nil, 'condition_operator' => nil,
                                                     'condition_value' => nil, 'condition_unit' => nil)
  end
end
