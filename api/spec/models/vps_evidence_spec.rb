require 'spec_helper'

RSpec.describe VpsEvidence do
  let(:now) { Time.at(1_795_608_005).utc }
  let(:vps) { build_standalone_vps_fixture.fetch(:vps) }
  let(:node) { vps.node }
  let(:settings) { VpsAdmin::API::Evidence::RtnlLatency::DEFAULTS.merge(enabled: true, threshold_seconds: 2) }

  before do
    allow(described_class).to receive(:config).and_call_original
    allow(described_class).to receive(:config).with('rtnl_latency').and_return(settings)
    allow(TransactionChains::IncidentReport::New).to receive(:fire).and_return([nil, nil])
    set_vps_running!(vps).update_columns(updated_at: now)
  end

  def event(sequence: 42, shift_us: 0, **overrides)
    data = JSON.parse(File.read(File.expand_path('../../../libnodectld/spec/fixtures/vps_evidence_v1.json', __dir__))).fetch('opts')
    data['targets'][0]['id'] = vps.id.to_s
    data['targets'][0]['pool'] = vps.pool.filesystem.split('/').first
    data['sequence'] = sequence
    data['batch_id'] = "#{data['signal']}:#{data['producer_epoch']}:#{sequence}"
    data['observed_at_us'] += shift_us
    data['observed_mono_us'] += shift_us
    data['targets'][0]['window_from_mono_us'] += shift_us
    data['targets'][0]['window_to_mono_us'] += shift_us
    data['segments'].each do |segment|
      %w[from_mono_us to_mono_us from_at_us to_at_us].each { |key| segment[key] += shift_us }
      %w[probe_started_mono_us probe_completed_mono_us coverage_started_mono_us].each { |key| segment['evidence'][key] += shift_us }
    end
    data.merge(overrides.stringify_keys)
  end

  def ingest(data = event, at: now)
    travel_to(at) { described_class.ingest!(node, data) }
  end

  def state
    VpsEvidenceState.find_by!(vps:, signal: 'rtnl_latency')
  end

  it 'accepts the canonical two seconds once and commits an immutable non-action incident' do
    expect(ingest).to eq(:accepted)
    expect(state.accepted_us).to eq(2_000_000)
    incident = IncidentReport.find_by!(vps:, codename: 'rtnl_latency')
    expect(incident).to have_attributes(source_kind: 'node_oomd_evidence', source_action: 'none', vps_action: 'none')
    expect(incident.evidence_snapshot).to include('threshold_seconds' => 2, 'credit_us' => 2_000_000, 'window_complete' => false)
    expect(incident.vps_evidence_intervals.sole.credit_us).to eq(2_000_000)
    expect(ObjectHistory.where(tracked_object: vps)).to be_empty
    expect(ingest).to eq(:duplicate)
    expect(state.accepted_us).to eq(2_000_000)
    expect(IncidentReport.where(vps:).count).to eq(1)
  end

  it 'rejects conflicting identity reuse and accepts reordered object keys as the same facts' do
    ingest
    reordered = event.to_a.reverse.to_h
    expect(ingest(reordered)).to eq(:duplicate)
    expect { ingest(event.merge('roster_complete' => false)) }.to raise_error(described_class::InvalidEvent)
    expect(state.accepted_us).to eq(2_000_000)
  end

  it 'rejects stale/future events, floats, oversized fields and a false integer identity' do
    [event.merge('observed_at_us' => 0), event.merge('observed_at_us' => (now.to_i + 3) * 1_000_000),
     event.merge('interval_us' => 5.0), event.merge('producer_epoch' => 'x' * 20_000), event.merge('sequence' => true)].each do |data|
      expect { ingest(data) }.to raise_error(described_class::InvalidEvent)
    end
    expect(VpsEvidenceEvent.count).to eq(0)
  end

  it 'requires previous and current qualification, exact tails and exact UTC mapping' do
    variants = [event, event, event, event]
    variants[0]['targets'][0]['previous_qualification'] = 'ineligible'
    variants[1]['segments'][0]['from_mono_us'] -= 1
    variants[2]['segments'][0]['from_at_us'] += 1
    variants[3]['segments'][0]['credit_us'] += 1
    variants.each { |data| expect { ingest(data) }.to raise_error(described_class::InvalidEvent) }
  end

  it 'credits received partial parts at threshold and does not require whole-window completeness' do
    data = event(parts: 2)
    ingest(data)
    expect(state.accepted_us).to eq(2_000_000)
    expect(IncidentReport.where(vps:).count).to eq(1)
    expect(IncidentReport.where(vps:).sole.evidence_snapshot['window_complete']).to be(false)
    second = Marshal.load(Marshal.dump(data))
    second['part'] = 2
    second['segments'] = []
    expect(ingest(second)).to eq(:accepted)
    expect(state.accepted_us).to eq(2_000_000)
  end

  it 'unions pending and completed overlap rather than counting the pending tail again' do
    pending = event
    pending['segments'][0]['evidence']['probe_completed_mono_us'] = nil
    pending['segments'][0].merge!('to_mono_us' => 12_000_000,
                                  'to_at_us' => pending['observed_at_us'] - 3_000_000, 'credit_us' => 1_000_000,
                                  'peak_value' => 5_000_000, 'peak_is_lower_bound' => true)
    ingest(pending)
    # A later part contains the completion facts for the same occurrence.
    completed = event(sequence: 43)
    completed['observed_at_us'] += 1_000_000
    completed['observed_mono_us'] += 1_000_000
    completed['targets'][0]['window_to_mono_us'] += 1_000_000
    ingest(completed, at: now + 1)
    expect(state.accepted_us).to eq(2_000_000)
    expect(VpsEvidenceInterval.live.where(vps:).sum(:credit_us)).to eq(2_000_000)
  end

  it 'preserves an ineligible newer proof against a late qualified part' do
    ingest(event(parts: 2))
    negative = event(sequence: 43, shift_us: 5_000_000)
    negative['segments'] = []
    negative['targets'][0]['qualification'] = 'ineligible'
    ingest(negative, at: now + 5)
    late = event(parts: 2, part: 2)
    late['segments'] = []
    ingest(late, at: now + 6)
    expect(state.target['qualification']).to eq('ineligible')
    expect(described_class.projection(vps, state, now: now + 6, settings:)[:fresh]).to be(false)
  end

  it 'retains same-owner credit across current node/run changes but rejects former-node input' do
    ingest
    original_pool = vps.pool.filesystem
    vps.pool.update_column(:filesystem, 'another-pool/vps')
    expect(described_class.projection(vps, state, now:, settings:)[:fresh]).to be(false)
    vps.pool.update_column(:filesystem, original_pool)
    vps.vps_current_status.update_columns(updated_at: now + 3)
    expect(described_class.projection(vps, state, now:, settings:)[:fresh]).to be(false)
    vps.vps_current_status.update_columns(updated_at: now)
    vps.update_column(:node_id, SpecSeed.other_node.id)
    expect(ingest(event(sequence: 43, shift_us: 5_000_000), at: now + 5)).to eq(:accepted)
    expect(state.accepted_us).to eq(2_000_000)
    expect(described_class.projection(vps.reload, state, now: now + 5, settings:)[:fresh]).to be(false)
  end

  it 'excludes pre-owner and boundary-crossing intervals, resets reporting state on transfer' do
    ingest
    vps.update_columns(user_id: SpecSeed.other_user.id, incident_accounting_since: now + 1)
    current = event(sequence: 43, shift_us: 5_000_000)
    ingest(current, at: now + 5)
    expect(state).to have_attributes(user_id: SpecSeed.other_user.id, accepted_us: 2_000_000, last_incident_at: now + 5)
    expect(described_class.projection(vps.reload, state, now: now + 5, settings:)[:credit_us]).to eq(2_000_000)
    # Old evidence remains immutable and attributed to its original owner.
    expect(IncidentReport.where(vps:).order(:id).first.user_id).not_to eq(vps.user_id)
  end

  it 'expires clipped rolling credit without new arrivals while preserving the accepted counter' do
    ingest
    facts = described_class.projection(vps, state, now: now + 86_399, settings:)
    expect(facts[:credit_us]).to eq(0)
    expect(facts[:accepted_us]).to eq(2_000_000)
    expect(facts[:report_due]).to be(false)
  end

  it 'does not repeat from stale proof or catch up, and repeats at exact period with fresh zero-credit proof' do
    ingest
    travel_to(now + 60) { described_class.process!(vps, 'rtnl_latency') }
    expect(IncidentReport.where(vps:).count).to eq(1)
    settings[:repeat_seconds] = 60
    heartbeat = event(sequence: 43, shift_us: 60_000_000, kind: 'heartbeat', segments: [])
    vps.vps_current_status.update_columns(updated_at: now + 60)
    ingest(heartbeat, at: now + 60)
    expect(IncidentReport.where(vps:).count).to eq(2)
    expect(state.last_incident_at).to eq(now + 60)
    travel_to(now + 60) { described_class.process!(vps, 'rtnl_latency') }
    expect(IncidentReport.where(vps:).count).to eq(2)
  end

  it 'rolls back receipt, intervals and repeat time when report creation fails' do
    allow(IncidentReport).to receive(:new).and_raise('report failed')
    expect { ingest }.to raise_error(RuntimeError, 'report failed')
    expect(VpsEvidenceEvent.count).to eq(0)
    expect(VpsEvidenceInterval.count).to eq(0)
    expect(VpsEvidenceState.count).to eq(0)
    expect(VpsEvidenceDailyTotal.count).to eq(0)
  end

  it 'invalidates retained proof on a new producer epoch even on a zero-target heartbeat' do
    ingest
    heartbeat = event(sequence: 1, shift_us: 5_000_000, kind: 'heartbeat', targets: [], segments: [])
    heartbeat['producer_epoch'] = 'b' * 32
    heartbeat['batch_id'] = "#{heartbeat['signal']}:#{heartbeat['producer_epoch']}:1"
    ingest(heartbeat, at: now + 5)
    expect(state.target).to be_nil
    expect(state.accepted_us).to eq(2_000_000)
  end

  it 'exports occurrence expiry, accepted counters, partial report readiness and bounded labels through the normal exporter' do
    ingest
    registry = Prometheus::Client::Registry.new
    allow(Prometheus::Client).to receive(:registry).and_return(registry)
    task = VpsAdmin::API::Tasks::Prometheus.new
    allow(Time).to receive(:now).and_return(now + 86_401)
    task.send(:export_vps_evidence)
    expect(registry.get(:vpsadmin_vps_evidence_credit_seconds).get(labels: { vps_id: vps.id, signal: 'rtnl_latency' })).to eq(0)
    counter = registry.get(:vpsadmin_vps_evidence_accepted_seconds_total)
    expect(counter.get(labels: { vps_id: vps.id, signal: 'rtnl_latency' })).to eq(2)
    expect(counter.labels).to eq(%i[vps_id signal])
    expect(registry.get(:vpsadmin_vps_evidence_threshold_seconds).get(labels: { signal: 'rtnl_latency' })).to eq(2)
    expect(registry.get(:vpsadmin_vps_evidence_report_due).get(labels: { vps_id: vps.id, signal: 'rtnl_latency' })).to eq(0)
    expect(registry.get(:vpsadmin_vps_evidence_window_complete).get(labels: { vps_id: vps.id, signal: 'rtnl_latency' })).to eq(0)
  end

  it 'keeps report details and mail preview immutable through live ledger expiry and settings changes' do
    ingest
    incident = IncidentReport.find_by!(vps:, codename: 'rtnl_latency')
    original = incident.evidence_snapshot.deep_dup
    settings[:window_seconds] = 60
    settings[:threshold_seconds] = 20
    described_class.prune!(now: now + 120)
    expect(VpsEvidenceInterval.live.where(vps:).count).to eq(1) # Retained for receipt-time daily gains.
    described_class.prune!(now: now + 90_000)
    expect(VpsEvidenceInterval.live.where(vps:)).to be_empty
    expect(incident.reload.evidence_snapshot).to eq(original)
    preview = VpsAdmin::API::IncidentReports.vps_evidence_mail_projection(incident)
    expect(preview).to include(threshold_seconds: 2, total_count: 1, shown_count: 1, omitted_count: 0)
    expect(preview[:intervals].sole[:credit_us]).to eq(2_000_000)
  end

  it 'never certifies an enlarged window after smaller-window history has expired' do
    ingest
    state.update!(complete_since: now - 86_400)
    settings[:window_seconds] = 60
    described_class.prune!(now:)
    settings[:window_seconds] = 86_400
    expect(described_class.projection(vps, state.reload, now:, settings:)[:window_complete]).to be(false)
  end

  it 'keeps fresh current proof independent from incomplete roster and known history' do
    settings[:repeat_seconds] = 60
    ingest
    heartbeat = event(sequence: 43, shift_us: 60_000_000, kind: 'heartbeat', segments: [], roster_complete: false,
                      targets_complete: false, gap_since_previous: true, gap_reason: 'sample_gap')
    vps.vps_current_status.update_columns(updated_at: now + 60)
    ingest(heartbeat, at: now + 60)
    expect(IncidentReport.where(vps:).count).to eq(2)
    expect(IncidentReport.where(vps:).order(:id).last.evidence_snapshot['window_complete']).to be(false)
  end

  it 'rejects a same-epoch clock step instead of crediting linked time' do
    ingest
    changed = event(sequence: 43, shift_us: 5_000_000)
    changed['observed_at_us'] += 1_000_001
    changed['segments'].each do |segment|
      segment['from_at_us'] += 1_000_001
      segment['to_at_us'] += 1_000_001
    end
    expect { ingest(changed, at: now + 7) }.to raise_error(described_class::InvalidEvent, /clock discontinuity/)
    expect(state.accepted_us).to eq(2_000_000)
  end

  it 'validates independent configuration bounds and rejects events with an incompatible sampling interval' do
    expect { described_class.config('rtnl_latency', window_seconds: 59) }.to raise_error(ArgumentError)
    expect { described_class.config('rtnl_latency', window_seconds: 60, threshold_seconds: 61) }.to raise_error(ArgumentError)
    expect { described_class.config('rtnl_latency', repeat_seconds: 59) }.to raise_error(ArgumentError)
    expect { described_class.config('rtnl_latency', freshness_seconds: 301) }.to raise_error(ArgumentError)
    settings[:freshness_seconds] = 10
    expect { ingest }.to raise_error(described_class::InvalidEvent)
  end

  it 'accepts a qualified bound proof without inventing an exact rank for partial peer data' do
    data = event
    data['targets'][0]['qualification_evidence']['rank'] = nil
    data['roster_complete'] = false
    ingest(data)
    expect(state.accepted_us).to eq(2_000_000)
    expect(IncidentReport.where(vps:).sole.evidence_snapshot['window_complete']).to be(false)
  end

  it 'enforces the exact configurable 300-second threshold on persisted clipped intervals' do
    settings[:threshold_seconds] = 300
    ingest
    # Seed previously accepted disjoint time, leaving the current source event
    # as the freshness/run authority. The final microsecond crosses threshold.
    VpsEvidenceInterval.create!(vps:, signal: 'rtnl_latency', user: vps.user, accounting_since: vps.incident_accounting_since,
                                from_at: now - 301, to_at: now - Rational(3_000_001, 1_000_000),
                                credit_us: 297_999_999, accepted_at: now - 2, measurement: 'rtnl_latency', peak_unit: 'microseconds', peak_value: 400_000_000, peak_is_lower_bound: false, evidence: {})
    travel_to(now) { described_class.process!(vps, 'rtnl_latency') }
    expect(IncidentReport.where(vps:)).to be_empty
    VpsEvidenceInterval.create!(vps:, signal: 'rtnl_latency', user: vps.user, accounting_since: vps.incident_accounting_since,
                                from_at: now - Rational(3_000_001, 1_000_000), to_at: now - 3,
                                credit_us: 1, accepted_at: now - 2, measurement: 'rtnl_latency', peak_unit: 'microseconds', peak_value: 400_000_000, peak_is_lower_bound: false, evidence: {})
    travel_to(now) { described_class.process!(vps, 'rtnl_latency') }
    expect(IncidentReport.where(vps:).sole.evidence_snapshot['credit_us']).to eq(300_000_000)
  end

  %w[en cs].each do |language|
    it "renders actual non-default settings and partial evidence in #{language} through ordinary mail" do
      settings.merge!(window_seconds: 60, threshold_seconds: 2, repeat_seconds: 120)
      vps.user.update!(language: Language.find_by!(code: language))
      ensure_alert_mail_templates!
      ensure_mailer_available!
      allow(TransactionChains::IncidentReport::New).to receive(:fire).and_call_original
      unlock_transaction_signer!
      with_current_context(user: SpecSeed.admin) do
        ingest(event(roster_complete: false))
      end
      incident = IncidentReport.find_by!(vps:, codename: 'rtnl_latency')
      expect(incident.text).to include('60 s', '120 s', '2 s', 'UTC')
      expect(incident.text).to include(language == 'en' ? '1 of 1' : '1 z 1')
      expect(incident.text).not_to include('translation missing', '%{', '86400')
      expect(incident.evidence_snapshot).to include('window_seconds' => 60, 'window_complete' => false)
      mail = MailLog.find_by!(user: vps.user, mail_template: MailTemplate.find_by!(name: 'vps_incident_report'))
      expect(mail.text_plain).to include(incident.text)
      expect(mail.text_html).to include(ERB::Util.html_escape(incident.text)) if mail.text_html
    end
  end

  it 'permits a repeat at exact 86400-second equality without a below-threshold rearm' do
    settings[:enabled] = false
    ingest
    state.update!(last_incident_at: now - 86_400 + Rational(1, 1_000_000))
    settings[:enabled] = true
    travel_to(now) { described_class.process!(vps, 'rtnl_latency') }
    expect(IncidentReport.where(vps:)).to be_empty
    state.update!(last_incident_at: now - 86_400)
    travel_to(now) { described_class.process!(vps, 'rtnl_latency') }
    expect(IncidentReport.where(vps:).count).to eq(1)
  end

  it 'accepts a late retired-epoch part once without moving active proof or stream state backwards' do
    settings[:enabled] = false
    ingest(event(parts: 2))
    current = event(sequence: 1, shift_us: 5_000_000, segments: [])
    current['producer_epoch'] = 'b' * 32
    current['batch_id'] = "#{current['signal']}:#{current['producer_epoch']}:1"
    current['targets'][0]['run']['init_pid'] += 1
    ingest(current, at: now + 5)
    proof = state.attributes.deep_dup
    late = event(parts: 2, part: 2)
    late['segments'][0]['evidence'].merge!('probe' => 78, 'probe_started_mono_us' => 13_000_000, 'probe_completed_mono_us' => 15_000_000)
    late['segments'][0].merge!('from_mono_us' => 14_000_000,
                               'to_mono_us' => 15_000_000, 'from_at_us' => late['observed_at_us'] - 1_000_000,
                               'to_at_us' => late['observed_at_us'], 'credit_us' => 1_000_000, 'peak_value' => 2_000_000)
    ingest(late, at: now + 6)
    expect(state.accepted_us).to eq(3_000_000)
    expect(state.attributes.except('accepted_us')).to eq(proof.except('accepted_us'))
    expect(ingest(late, at: now + 7)).to eq(:duplicate)
    expect(state.accepted_us).to eq(3_000_000)
    expect(VpsEvidenceEvent.where(node:, current_stream: true).order(id: :desc).first.producer_epoch).to eq('b' * 32)
    # The next live B observation still follows B, rather than the latest insert.
    current['sequence'] = 2
    current['batch_id'] = "#{current['signal']}:#{current['producer_epoch']}:2"
    current['sample_sequence'] += 1
    current['observed_at_us'] += 5_000_000
    current['observed_mono_us'] += 5_000_000
    current['targets'][0]['window_from_mono_us'] += 5_000_000
    current['targets'][0]['window_to_mono_us'] += 5_000_000
    ingest(current, at: now + 10)
    expect(state.target.dig('source', 'sequence')).to eq(2)
    expect(state.target.dig('source', 'producer_epoch')).to eq('b' * 32)
  end

  it 'does not permanently retire a clock-reset epoch before its first current observation' do
    settings[:enabled] = false
    ingest
    reset = event(sequence: 1, shift_us: 5_000_000, segments: [])
    reset['producer_epoch'] = 'c' * 32
    reset['batch_id'] = "#{reset['signal']}:#{reset['producer_epoch']}:1"
    reset['observed_at_us'] -= 6_000_000
    ingest(reset, at: now + 5)
    expect(state.target).to be_nil
    reset['sequence'] = 2
    reset['batch_id'] = "#{reset['signal']}:#{reset['producer_epoch']}:2"
    reset['sample_sequence'] += 1
    reset['observed_at_us'] += 5_000_000
    reset['observed_mono_us'] += 5_000_000
    reset['targets'][0]['window_from_mono_us'] += 5_000_000
    reset['targets'][0]['window_to_mono_us'] += 5_000_000
    ingest(reset, at: now + 10)
    expect(state.target.dig('source', 'producer_epoch')).to eq('c' * 32)
    expect(described_class.projection(vps, state, now: now + 10, settings:)[:fresh]).to be(true)
  end

  def seed_target(target, previous: 'unknown')
    target.merge('qualification' => 'qualified', 'previous_qualification' => previous,
                 'linked' => false, 'window_from_mono_us' => nil, 'window_to_mono_us' => nil,
                 'reason' => 'initial_baseline')
  end

  # Run the real serialization/read, advancing the existing test clock where a
  # lock wait would have elapsed. No sleeps or alternate clock implementation.
  def delay_serialization_until(time)
    advanced = false
    allow(IncidentEscalation).to receive(:serialized).and_wrap_original do |original, *args, **options, &block|
      original.call(*args, **options) do |locked|
        unless advanced
          travel_to(time)
          advanced = true
        end
        block.call(locked)
      end
    end
  end

  def delay_state_read_until(time, vps_id: vps.id)
    allow(VpsEvidenceState).to receive(:lock).and_wrap_original do |original, *args|
      relation = original.call(*args)
      allow(relation).to receive(:find_or_initialize_by).and_wrap_original do |finder, attributes|
        row = finder.call(attributes)
        travel_to(time) if attributes[:vps_id] == vps_id
        row
      end
      relation
    end
  end

  def add_target(data, other)
    target = data['targets'].first.deep_dup
    target['id'] = other.id.to_s
    target['pool'] = other.pool.name
    target['run']['group_path'] = "/osctl/pool.#{other.pool.name}/ct.#{other.id}"
    target['run']['init_pid'] += 1
    data['targets'] << target
    target
  end

  it 'accepts a producer-shaped first qualified seed without credit or reporting eligibility' do
    data = event(segments: [])
    data['targets'][0] = seed_target(data['targets'][0])
    expect(ingest(data)).to eq(:accepted)
    expect(state.accepted_us).to eq(0)
    expect(state.target).to include('qualification' => 'qualified', 'linked' => false)
    expect(VpsEvidenceInterval.where(vps:)).to be_empty
    expect(IncidentReport.where(vps:)).to be_empty
    expect(described_class.projection(vps, state, now:, settings:)).to include(fresh: false, report_due: false)
  end

  %w[new_run broken_link].each do |kind|
    it "retains historical threshold credit but cannot report from a qualified #{kind} seed" do
      settings[:enabled] = false
      ingest
      settings[:enabled] = true
      data = event(sequence: 43, shift_us: 5_000_000, segments: [])
      previous = kind == 'new_run' ? 'unknown' : 'qualified'
      data['targets'][0] = seed_target(data['targets'][0], previous:)
      data['targets'][0]['run']['init_start_time_ticks'] += 1 if kind == 'new_run'
      ingest(data, at: now + 5)
      expect(state.accepted_us).to eq(2_000_000)
      expect(VpsEvidenceInterval.live.where(vps:).sum(:credit_us)).to eq(2_000_000)
      expect(IncidentReport.where(vps:)).to be_empty
      expect(described_class.projection(vps, state, now: now + 5, settings:)).to include(fresh: false, report_due: false)
    end
  end

  it 'accepts a mixed part without letting a seed poison a linked target contribution' do
    other = build_standalone_vps_fixture(node:).fetch(:vps)
    set_vps_running!(other).update_columns(updated_at: now)
    data = event
    add_target(data, other)
    data['targets'][0] = seed_target(data['targets'][0])
    data['segments'][0]['target'] = 1
    expect(ingest(data)).to eq(:accepted)
    expect(state.accepted_us).to eq(0)
    expect(VpsEvidenceState.find_by!(vps: other).accepted_us).to eq(2_000_000)
    expect(IncidentReport.where(vps:)).to be_empty
    expect(IncidentReport.where(vps: other).sole.evidence_snapshot['credit_us']).to eq(2_000_000)
  end

  it 'rejects an unlinked contribution atomically even when the current target is qualified' do
    data = event
    data['targets'][0] = seed_target(data['targets'][0], previous: 'qualified')
    expect { ingest(data) }.to raise_error(described_class::InvalidEvent)
    expect(VpsEvidenceEvent.count).to eq(0)
    expect(VpsEvidenceState.count).to eq(0)
    expect(VpsEvidenceInterval.count).to eq(0)
    expect(IncidentReport.where(vps:)).to be_empty
  end

  it 'retains typed run, resource and rank guards for qualified seeds' do
    variants = 4.times.map do
      data = event(segments: [])
      data['targets'][0] = seed_target(data['targets'][0])
      data
    end
    variants[0]['targets'][0]['run'] = nil
    variants[1]['targets'][0]['run']['init_pid'] = false
    variants[2]['targets'][0]['qualification_evidence']['cpu_limit_state'] = 'unknown'
    variants[3]['targets'][0]['qualification_evidence']['rank'] = 0
    variants.each { |data| expect { ingest(data) }.to raise_error(described_class::InvalidEvent) }
    expect(VpsEvidenceEvent.count).to eq(0)
  end

  it 'rejects a fresh intake that expires during serialization without accepting a receipt or proof' do
    delay_serialization_until(now + 31)
    expect { ingest }.to raise_error(described_class::InvalidEvent)
    expect(VpsEvidenceEvent.count).to eq(0)
    expect(VpsEvidenceState.count).to eq(0)
    expect(VpsEvidenceInterval.count).to eq(0)
    expect(IncidentReport.where(vps:)).to be_empty
  end

  it 'rolls back an expired new epoch after a state wait without replacing accepted history or proof' do
    settings[:enabled] = false
    ingest
    original = state.attributes.deep_dup
    data = event(sequence: 1, shift_us: 5_000_000, kind: 'heartbeat', segments: [])
    data['producer_epoch'] = 'd' * 32
    data['batch_id'] = "#{data['signal']}:#{data['producer_epoch']}:1"
    delay_state_read_until(now + 36)
    expect { ingest(data, at: now + 5) }.to raise_error(described_class::InvalidEvent)
    expect(state.attributes).to eq(original)
    expect(VpsEvidenceEvent.count).to eq(1)
    expect(VpsEvidenceInterval.live.where(vps:).sum(:credit_us)).to eq(2_000_000)
  end

  it 'rechecks each target after its own state wait and rolls back the entire expired part' do
    other = build_standalone_vps_fixture(node:).fetch(:vps)
    set_vps_running!(other).update_columns(updated_at: now)
    data = event
    add_target(data, other)
    data['segments'] << data['segments'][0].merge('target' => 1)
    delay_state_read_until(now + 31, vps_id: other.id)
    expect { ingest(data) }.to raise_error(described_class::InvalidEvent)
    expect(VpsEvidenceEvent.count).to eq(0)
    expect(VpsEvidenceState.count).to eq(0)
    expect(VpsEvidenceInterval.count).to eq(0)
    expect(IncidentReport.where(vps_id: [vps.id, other.id])).to be_empty
  end

  it 'records the real post-wait decision while preserving intake receipt and duplicate identity' do
    delay_state_read_until(now + 5)
    ingest
    receipt = VpsEvidenceEvent.sole
    incident = IncidentReport.where(vps:).sole
    expect(receipt.received_at).to eq(now)
    expect(receipt.observed_at).to eq(now)
    expect(incident.detected_at).to eq(now + 5)
    expect(incident.evidence_snapshot).to include('evaluated_at' => (now + 5).iso8601(6),
                                                  'window_to' => (now + 5).iso8601(6),
                                                  'window_from' => (now + 5 - settings[:window_seconds]).iso8601(6))
    expect(state.last_incident_at).to eq(now + 5)
    expect(ingest(at: now + 6)).to eq(:duplicate)
    expect(receipt.reload.received_at).to eq(now)
    expect(IncidentReport.where(vps:).count).to eq(1)
  end

  it 'does not report from a proof that expires during periodic serialization' do
    settings[:enabled] = false
    ingest
    settings[:enabled] = true
    delay_serialization_until(now + 31)
    travel_to(now) { described_class.process!(vps, 'rtnl_latency') }
    expect(IncidentReport.where(vps:)).to be_empty
    expect(state.accepted_us).to eq(2_000_000)
  end

  it 'checks current status age at the periodic decision even while the observation is fresh' do
    settings[:enabled] = false
    ingest
    settings[:enabled] = true
    vps.vps_current_status.update_columns(updated_at: now - 29)
    delay_state_read_until(now + 2)
    travel_to(now) { described_class.process!(vps, 'rtnl_latency') }
    expect(IncidentReport.where(vps:)).to be_empty
    expect(state.accepted_us).to eq(2_000_000)
  end

  it 'uses a periodic post-wait decision when a repeat becomes due while waiting' do
    settings[:repeat_seconds] = 60
    ingest
    heartbeat = event(sequence: 43, shift_us: 55_000_000, kind: 'heartbeat', segments: [])
    vps.vps_current_status.update_columns(updated_at: now + 55)
    ingest(heartbeat, at: now + 55)
    expect(IncidentReport.where(vps:).count).to eq(1)
    delay_state_read_until(now + 60)
    travel_to(now + 55) { described_class.process!(vps, 'rtnl_latency') }
    incident = IncidentReport.where(vps:).order(:id).last
    expect(IncidentReport.where(vps:).count).to eq(2)
    expect(incident.detected_at).to eq(now + 60)
    expect(incident.evidence_snapshot).to include('evaluated_at' => (now + 60).iso8601(6),
                                                  'window_to' => (now + 60).iso8601(6),
                                                  'window_from' => (now + 60 - settings[:window_seconds]).iso8601(6))
    expect(state.last_incident_at).to eq(now + 60)
  end

  it 'rejects unknown signal, representation and measurement metadata before persisting' do
    variants = [event(signal: 'unknown'), event(representation: 'snapshot'), event]
    variants.last['segments'][0]['peak_unit'] = 'seconds'
    variants << event
    variants.last['segments'][0]['measurement'] = 'arbitrary'
    variants << event
    variants.last['segments'][0]['peak_value'] = nil
    variants << event
    %w[measurement peak_unit peak_value peak_is_lower_bound].each { |key| variants.last['segments'][0][key] = nil }
    variants.each { |data| expect { ingest(data) }.to raise_error(described_class::InvalidEvent) }
    expect(VpsEvidenceEvent.count).to eq(0)
    expect(VpsEvidenceInterval.count).to eq(0)
  end

  it 'preserves native relative run paths exactly and rejects unsafe component variants' do
    data = event
    path = "osctl/pool.tank/ct.#{vps.id}/user-owned"
    data['targets'][0]['run']['group_path'] = path
    expect(ingest(data)).to eq(:accepted)
    expect(state.target.dig('run', 'group_path')).to eq(path)
    expect(state.accepted_us).to eq(2_000_000)
    ['', '/', '///', 'osctl/./ct', 'osctl/../ct', "osctl/ct\n"].each do |invalid|
      variant = event(sequence: 43)
      variant['targets'][0]['run']['group_path'] = invalid
      expect { ingest(variant) }.to raise_error(described_class::InvalidEvent)
    end
    expect(data['targets'][0]['run']).not_to eq(event['targets'][0]['run'])
  end

  it 'isolates real receipt cursors, intervals, proofs, counters and repeat state by signal' do
    second = Class.new do
      const_set(:SIGNAL, 'test_duration')
      const_set(:REPRESENTATION, 'qualified_duration')
      const_set(:CATEGORY, 'vps_evidence_test_duration')
      const_set(:DEFAULTS, VpsAdmin::API::Evidence::RtnlLatency::DEFAULTS)
      def self.validate_context!(payload)
        payload.keys!(payload.data['signal_context'], [])
      end

      def self.validate_target!(payload, target)
        payload.keys!(target['qualification_evidence'], [])
      end

      def self.validate_segment!(payload, segment, target)
        payload.check(target['linked'] && target['qualification'] == 'qualified' && target['previous_qualification'] == 'qualified')
        payload.keys!(segment['evidence'], [])
        payload.check(segment.values_at('measurement', 'peak_unit', 'peak_value', 'peak_is_lower_bound').all?(&:nil?))
      end

      def self.condition(_data)
        nil
      end

      def self.eligible?(data, target)
        data['coverage_valid'] && target['linked'] && target['qualification'] == 'qualified'
      end

      def self.message(**)
        { subject: 'Synthetic duration evidence', text: 'Test-only signal definition' }
      end
    end
    stub_const('VpsEvidence::SIGNALS', described_class::SIGNALS.merge(second::SIGNAL => second))
    allow(described_class).to receive(:config).with(second::SIGNAL).and_return(settings.dup)
    other = event(signal: second::SIGNAL, signal_context: {})
    other['batch_id'] = "#{second::SIGNAL}:#{other['producer_epoch']}:42"
    other['targets'][0]['qualification_evidence'] = {}
    other['segments'][0]['evidence'] = {}
    %w[measurement peak_unit peak_value peak_is_lower_bound].each { |key| other['segments'][0][key] = nil }
    expect(ingest).to eq(:accepted)
    expect(ingest(other)).to eq(:accepted)
    expect(ingest(other)).to eq(:duplicate)
    expect(VpsEvidenceEvent.where(node:, sequence: 42).pluck(:signal)).to contain_exactly('rtnl_latency', second::SIGNAL)
    states = VpsEvidenceState.where(vps:).index_by(&:signal)
    expect(states.values.map(&:accepted_us)).to eq([2_000_000, 2_000_000])
    expect(VpsEvidenceInterval.live.where(vps:).group(:signal).sum(:credit_us)).to eq('rtnl_latency' => 2_000_000, second::SIGNAL => 2_000_000)
    expect(IncidentReport.where(vps:).pluck(:codename)).to contain_exactly('rtnl_latency', second::SIGNAL)
    expect(IncidentReport.where(vps:).pluck(:source_key).uniq.length).to eq(2)
    expect(IncidentReport.find_by!(vps:, codename: second::SIGNAL).evidence_snapshot).to include('signal' => second::SIGNAL, 'condition' => nil)
    expect(VpsEvidenceInterval.where(signal: second::SIGNAL).pluck(:measurement, :peak_unit, :peak_value, :peak_is_lower_bound).uniq).to eq([[nil, nil, nil, nil]])
    before = state.attributes
    new_epoch = other.deep_dup
    new_epoch.merge!('producer_epoch' => 'd' * 32, 'sequence' => 1, 'kind' => 'heartbeat', 'segments' => [], 'targets' => [])
    new_epoch['batch_id'] = "#{second::SIGNAL}:#{new_epoch['producer_epoch']}:1"
    new_epoch['observed_at_us'] += 1_000_000
    new_epoch['observed_mono_us'] += 1_000_000
    expect(ingest(new_epoch, at: now + 1)).to eq(:accepted)
    expect(state.reload.attributes).to eq(before)
    expect(VpsEvidenceState.find_by!(vps:, signal: second::SIGNAL).target).to be_nil
    expect(VpsEvidenceInterval.live.where(signal: 'rtnl_latency', vps:).sum(:credit_us)).to eq(2_000_000)
  end

  it 'dispatches the typed node-scoped event through the authenticated supervisor boundary' do
    require 'vpsadmin/supervisor/node/vps_events'
    receiver = VpsAdmin::Supervisor::Node::VpsEvents.allocate
    allow(receiver).to receive(:node).and_return(node)
    travel_to(now) do
      expect(receiver.send(:process_event, { 'id' => nil, 'type' => 'vps_evidence', 'time' => now.to_i, 'opts' => event })).to eq(:accepted)
    end
    expect(state.accepted_us).to eq(2_000_000)
    expect(VpsEvidenceEvent.where(node:, signal: 'rtnl_latency').sole.facts).to eq(event)
  end
end
