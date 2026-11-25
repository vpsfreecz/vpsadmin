RSpec.shared_context 'with accepted VPS evidence fixture' do
  def accepted_evidence_fixture(vps, observed_at:, accepted_at: observed_at, sequence: 42)
    data = JSON.parse(File.read(File.expand_path('../../../libnodectld/spec/fixtures/vps_evidence_v1.json', __dir__))).fetch('opts')
    utc_delta = (observed_at.to_r * 1_000_000).to_i - data.fetch('observed_at_us')
    mono_delta = (observed_at.to_r * 1_000_000).to_i - data.fetch('observed_mono_us')
    data['observed_at_us'] += utc_delta
    %w[observed_mono_us coverage_started_mono_us].each { |key| data[key] += mono_delta }
    data['sequence'] = sequence
    data['batch_id'] = "#{data['signal']}:#{data['producer_epoch']}:#{sequence}"
    target = data['targets'].first
    target.merge!('id' => vps.id.to_s, 'pool' => vps.pool.filesystem.split('/').first)
    %w[window_from_mono_us window_to_mono_us].each { |key| target[key] += mono_delta }
    data['segments'].each do |segment|
      %w[from_mono_us to_mono_us].each { |key| segment[key] += mono_delta }
      %w[from_at_us to_at_us].each { |key| segment[key] += utc_delta }
      %w[probe_started_mono_us probe_completed_mono_us coverage_started_mono_us].each { |key| segment['evidence'][key] += mono_delta }
    end
    status = VpsCurrentStatus.find_by(vps_id: vps.id) || set_vps_running!(vps)
    status.update_columns(status: true, is_running: true, updated_at: observed_at)
    travel_to(accepted_at, with_usec: true) { VpsEvidence.ingest!(vps.node, data) }
    data
  end
end
