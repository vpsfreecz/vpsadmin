require_relative '../lib/vpsadmin/api/vps_evidence_configuration'

# Central accounting uses accepted occurrence time; reads never drive reports.
class VpsEvidence
  def self.ingest!(node, data)
    received_at = Time.now.utc
    # Parse and bound work before locks. Re-read settings inside serialization.
    handler = definition(data.is_a?(Hash) && data['signal'])
    signal = handler::SIGNAL
    payload = VpsAdmin::API::VpsEvidencePayload.new(data, now: received_at, config: config(signal))
    touched = []
    IncidentEscalation.serialized(nil, requires_new: true) do
      settings = config(signal)
      Node.lock.find(node.id)
      payload = VpsAdmin::API::VpsEvidencePayload.new(data, now: Time.now.utc, config: settings)
      identity = { node_id: node.id, signal:, producer_epoch: data['producer_epoch'], sequence: data['sequence'], part: data['part'] }
      existing = VpsEvidenceEvent.lock.find_by(identity)
      if existing
        raise InvalidEvent, 'Conflicting VPS evidence identity' unless existing.digest == payload.digest

        return :duplicate
      end
      parts = VpsEvidenceEvent.where(identity.except(:part)).order(:part).lock.to_a
      raise InvalidEvent, 'Conflicting VPS evidence headers' if parts.any? { |part| part.facts.except('part', 'targets', 'segments') != payload.header }

      previous = VpsEvidenceEvent.where(node_id: node.id, signal:, current_stream: true).order(id: :desc).lock.first
      current_epoch = previous.nil? || previous.producer_epoch == data['producer_epoch'] ||
                      !VpsEvidenceEvent.where(node_id: node.id, signal:, producer_epoch: data['producer_epoch'], current_stream: true).exists?
      latest = current_epoch && (previous.nil? || payload.observed_at > previous.observed_at ||
                 (previous.producer_epoch == data['producer_epoch'] && data['sequence'] >= previous.sequence && payload.observed_at == previous.observed_at))
      if previous && previous.producer_epoch == data['producer_epoch'] && data['sequence'] > previous.sequence
        mono_delta = data['observed_mono_us'] - previous.facts.fetch('observed_mono_us')
        utc_delta = data['observed_at_us'] - previous.facts.fetch('observed_at_us')
        raise InvalidEvent, 'VPS evidence clock discontinuity' unless mono_delta > 0 && (mono_delta - utc_delta).abs <= 1_000_000
      end
      repeated_targets = parts.flat_map { |part| part.facts.fetch('targets') }
      data['targets'].each do |target|
        old = repeated_targets.find { |entry| entry.values_at('pool', 'id') == target.values_at('pool', 'id') }
        raise InvalidEvent, 'Conflicting VPS evidence target' if old && old != target
      end
      payload.validate_time!(now: Time.now.utc, config: settings)
      new_epoch = current_epoch && previous && previous.producer_epoch != data['producer_epoch']
      if new_epoch || (latest && previous && previous.facts.values_at('producer_epoch', 'boot_id', 'observer_epoch') != data.values_at('producer_epoch', 'boot_id', 'observer_epoch'))
        VpsEvidenceState.where(node_id: node.id, signal:).update_all(target: nil, observed_at: nil, complete_since: nil)
      end
      continuous = latest && previous && previous.producer_epoch == data['producer_epoch'] &&
                   ((previous.sequence == data['sequence'] && parts.length + 1 == data['parts']) ||
                    (previous.sequence + 1 == data['sequence'] && data['parts'] == 1 &&
                     VpsEvidenceEvent.where(node_id: node.id, signal:, producer_epoch: previous.producer_epoch, sequence: previous.sequence).count == previous.parts)) &&
                   payload.observed_at - previous.observed_at <= settings[:freshness_seconds] &&
                   !data['gap_since_previous'] && data['coverage_valid'] && data['targets_complete'] && data['roster_complete']
      # A source/receipt gap is visible for every retained target on this node,
      # including targets omitted from this bounded event.
      VpsEvidenceState.where(node_id: node.id, signal:).update_all(complete_since: nil) if latest && !continuous
      # This immutable marker means the receipt advanced the cursor when it
      # arrived. Late parts cannot move it; retained markers identify retired
      # epochs without mistaking a not-yet-current clock-reset seed for one.
      VpsEvidenceEvent.create!(identity.merge(current_stream: latest, parts: data['parts'], digest: payload.digest, observed_at: payload.observed_at, received_at:, facts: data))
      # Numeric VPS identity is a vpsAdmin boundary; non-vpsAdmin containers are
      # valid generic OS targets but never map by to_i/truncation.
      mapped = data['targets'].each_with_index.filter_map do |target, index|
        next unless target['id'].match?(/\A[1-9][0-9]*\z/) && target['id'].length <= 18

        [target['id'].to_i, index, target]
      end
      mapped.sort_by(&:first).each do |id, index, target|
        vps = Vps.lock.find_by(id:, node_id: node.id)
        next unless vps && vps.pool.filesystem.split('/').first == target['pool']

        IncidentEscalation.new(vps).reconcile_transfer!
        next if vps.incident_owner_transfer_chain_id || (vps.incident_accounting_since && payload.observed_at < vps.incident_accounting_since)

        state = state_for!(vps, signal)
        payload.validate_time!(now: Time.now.utc, config: settings)
        if latest && (state.observed_at.nil? || payload.observed_at > state.observed_at)
          source = data.slice('producer_epoch', 'boot_id', 'observer_epoch', 'sample_epoch', 'sample_sequence', 'sequence', 'observed_mono_us', 'interval_us', 'coverage_valid').merge('eligible' => payload.eligible?(target) == true, 'condition' => payload.condition)
          same_run = state.node_id == node.id && state.target && state.target['run'] == target['run'] &&
                     state.target['source'].slice('producer_epoch', 'boot_id', 'observer_epoch') == source.slice('producer_epoch', 'boot_id', 'observer_epoch')
          complete_since = continuous && same_run ? state.complete_since : nil
          complete_since ||= payload.observed_at if data['parts'] == parts.length + 1 && data['coverage_valid'] && data['targets_complete'] && data['roster_complete']
          state.assign_attributes(node_id: node.id, observed_at: payload.observed_at, target: target.merge('source' => source), complete_since:)
        end
        payload.intervals_for(index).each do |interval|
          accept_interval!(vps, state, interval, now: Time.now.utc, settings:)
        end
        state.save!
        decision_at = Time.now.utc
        payload.validate_time!(now: decision_at, config: settings)
        evaluate!(vps, state, now: decision_at, settings:)
        touched << vps.id
      end
      payload.validate_time!(now: Time.now.utc, config: settings)
    end
    touched.uniq.each { |id| IncidentEscalation.process!(Vps.find(id)) }
    :accepted
  end

  def self.state_for!(vps, signal)
    state = VpsEvidenceState.lock.find_or_initialize_by(vps_id: vps.id, signal:)
    if state.new_record? || state.user_id != vps.user_id || state.accounting_since != vps.incident_accounting_since
      state.assign_attributes(user_id: vps.user_id, accounting_since: vps.incident_accounting_since, accepted_us: 0,
                              last_incident_at: nil, complete_since: nil, observed_at: nil, target: nil, node_id: nil)
    end
    state
  end

  def self.accept_interval!(vps, state, interval, now:, settings:)
    first = interval.fetch(:from_at)
    last = interval.fetch(:to_at)
    # An ownership-boundary crossing is rejected as a whole, never relabelled.
    return if vps.incident_accounting_since && first < vps.incident_accounting_since
    return if last <= now - settings[:window_seconds] - settings[:freshness_seconds]

    pieces = [[first, last]]
    VpsEvidenceInterval.live.where(vps_id: vps.id, signal: state.signal, user_id: vps.user_id, accounting_since: vps.incident_accounting_since)
                       .where('from_at < ? AND to_at > ?', last, first).order(:from_at).lock.each do |old|
      pieces = pieces.flat_map do |a, b|
        if old.to_at <= a || old.from_at >= b
          [[a, b]]
        else
          [[a, [b, old.from_at].min], [[a, old.to_at].max, b]].select { |x, y| x < y }
        end
      end
    end
    pieces.each do |a, b|
      credit = ((b.to_r - a.to_r) * 1_000_000).to_i
      accepted_at = Time.now.utc
      VpsEvidenceInterval.create!(interval.merge(vps:, user_id: vps.user_id, signal: state.signal,
                                                 accounting_since: vps.incident_accounting_since,
                                                 from_at: a, to_at: b, credit_us: credit, accepted_at:))
      VpsEvidenceDailyTotal.record_piece!(vps:, signal: state.signal, from_at: a, to_at: b, accepted_at:)
      state.accepted_us += credit
    end
  end

  def self.projection(vps, state, now:, settings: config(state.signal))
    rows = VpsEvidenceInterval.in_window(vps, state.signal, settings, now:).filter_map { |row| row.clipped(from: now - settings[:window_seconds], to: now) }
    status = vps.vps_current_status
    facts = { user_id: vps.user_id, accounting_since: vps.incident_accounting_since,
              state_user_id: state&.user_id, state_accounting_since: state&.accounting_since,
              node_id: vps.node_id, state_node_id: state&.node_id, pool_name: vps.pool.name,
              transfer_pending: !vps.incident_owner_transfer_chain_id.nil?,
              vps_active: vps.object_state == 'active', owner_active: vps.user.object_state == 'active',
              observed_at: state&.observed_at, target: state&.target, complete_since: state&.complete_since,
              status_ok: status && status.status, status_running: status && status.is_running, status_updated_at: status&.updated_at,
              accepted_us: state&.accepted_us || 0, last_incident_at: state&.last_incident_at, credit_us: rows.sum { |row| row[:credit_us] } }
    project(facts, now:, settings:).merge(rows:)
  end

  # Shared pure decision projection for the ledger and authorized read snapshots.
  # The caller supplies captured facts; this method performs no database work.
  def self.project(facts, now:, settings:)
    active = facts[:state_user_id] == facts[:user_id] && facts[:state_accounting_since] == facts[:accounting_since]
    target = active && facts[:target]
    observed_at = active && facts[:observed_at]
    status_at = facts[:status_updated_at]
    fresh = observed_at && observed_at.between?(now - settings[:freshness_seconds], now + 2) &&
            facts[:state_node_id] == facts[:node_id] && !facts[:transfer_pending] &&
            target && target['pool'] == facts[:pool_name] && target.dig('source', 'eligible') == true &&
            facts[:status_ok] && facts[:status_running] && status_at &&
            status_at.between?(now - settings[:freshness_seconds], now + 2) && facts[:vps_active] && facts[:owner_active]
    credit = facts.fetch(:credit_us)
    due = settings[:enabled] && fresh && credit >= settings[:threshold_seconds] * 1_000_000 &&
          (!facts[:last_incident_at] || now >= facts[:last_incident_at] + settings[:repeat_seconds])
    { credit_us: credit, report_due: due == true, fresh: fresh == true,
      window_complete: active && !facts[:complete_since].nil? && facts[:complete_since] <= now - settings[:window_seconds] &&
        !observed_at.nil? && observed_at >= now - settings[:freshness_seconds],
      observation_age_seconds: observed_at ? [(now - observed_at).to_f, 0].max : nil,
      accepted_us: active ? facts[:accepted_us] : 0, last_incident_at: active ? facts[:last_incident_at] : nil }
  end

  def self.evaluate!(vps, state, now:, settings: config(state.signal))
    result = projection(vps, state, now:, settings:)
    return unless result[:report_due]

    snapshot = settings.stringify_keys.merge('schema' => 1, 'signal' => state.signal, 'representation' => definition(state.signal)::REPRESENTATION, 'condition' => state.target.dig('source', 'condition'), 'credit_us' => result[:credit_us],
                                             'evaluated_at' => now.iso8601(6), 'window_from' => (now - settings[:window_seconds]).iso8601(6),
                                             'window_to' => now.iso8601(6), 'window_complete' => result[:window_complete],
                                             'interval_count' => result[:rows].length, 'qualification_interval_us' => state.target.dig('source', 'interval_us'))
    key = Digest::SHA256.hexdigest([vps.id, state.signal, vps.user_id, vps.incident_accounting_since&.iso8601(6), now.iso8601(6)].join(':'))
    incident = IncidentReport.new(vps:, user: vps.user, codename: state.signal, detected_at: now,
                                  source_key: key, source_kind: 'node_oomd_evidence', source_node_id: vps.node_id, source_action: 'none',
                                  vps_action: 'none', evidence_snapshot: snapshot)
    incident.assign_attributes(definition(state.signal).message(vps:, user: vps.user, snapshot:, intervals: result[:rows].first(5)).slice(:subject, :text))
    incident.save!
    result[:rows].each do |row|
      VpsEvidenceInterval.create!(row.merge(vps:, signal: state.signal, user: vps.user, accounting_since: vps.incident_accounting_since, incident_report: incident))
    end
    state.update!(last_incident_at: now)
    incident
  end

  def self.process!(vps, signal)
    IncidentEscalation.serialized(vps, requires_new: true) do |locked|
      IncidentEscalation.new(locked).reconcile_transfer!
      state = state_for!(locked, signal)
      state.save!
      evaluate!(locked, state, now: Time.now.utc)
    end
    IncidentEscalation.process!(vps)
  end

  def self.prune!(now: Time.now.utc)
    VpsEvidenceDailyTotal.prune!(now:)
    SIGNALS.each_key do |signal|
      settings = config(signal)
      floor = now - settings[:window_seconds] - settings[:freshness_seconds]
      VpsEvidenceState.where(signal:).where('complete_since < ?', floor).update_all(complete_since: floor)
      VpsEvidenceInterval.live.where(signal:).where('to_at <= ? AND accepted_at < ?', floor, now - 86_400 - 300).delete_all
      cursors = VpsEvidenceEvent.where(signal:, current_stream: true).group(:node_id).maximum(:id).values
      VpsEvidenceEvent.where(signal:).where.not(id: cursors).where('received_at < ?', now - 600).delete_all
    end
  end
end
