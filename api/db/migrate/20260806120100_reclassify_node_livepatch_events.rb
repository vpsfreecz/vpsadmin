class ReclassifyNodeLivepatchEvents < ActiveRecord::Migration[8.1]
  LIVEPATCH_CHANGE = 2
  LIVEPATCH_INVENTORY_CHANGE = 7
  NODE_REPORT_SOURCE = 1
  INFERRED_CONFIDENCE = 1
  APPLIED_ACTION = 0
  PUBLIC_EVENT_TYPES = [0, 1, LIVEPATCH_CHANGE].freeze

  def up
    transaction do
      inventory_ids = availability_only_event_ids
      affected_node_ids = node_ids_for(inventory_ids)

      reclassify_inventory_events(inventory_ids)
      backfill_applied_actions
      repair_current_markers(affected_node_ids)
    end
  end

  # The original public interpretation cannot be reconstructed safely. Keep
  # the corrected classifications and all authoritative evidence on rollback.
  def down; end

  protected

  # The old reporter described the livepatch configured by the current system
  # closure, even when that module was not loaded. This made an availability
  # change look like a public livepatch lifecycle event.
  #
  # Relabel only events that are safe to recognize:
  #
  # 1. The candidate has nonempty livepatch evidence, but none of its rows show
  #    runtime activity.
  # 2. Its immediately preceding public event reports the same effective kernel
  #    release and has authoritative evidence.
  # 3. Either both observations are inactive inventory, or the previous event
  #    has a stable patch and the candidate contains only differently identified
  #    inactive inventory. The latter is the patch-2-loaded/patch-3-configured
  #    shape produced by the old reporter.
  #
  # Empty evidence and an inactive row for the same effective patch stay public
  # because they may represent a real removal. A later reboot is also safe: the
  # boot is a public event in this ordering and remains the current state even
  # when its software revisions are older than earlier observations.
  def availability_only_event_ids
    candidates = inactive_livepatch_event_candidates
    return [] if candidates.empty?

    previous_by_event_id = previous_public_events(candidates)
    evidence_ids = candidates.filter_map { |event| event['node_kernel_evidence_id'] }
    evidence_ids.concat(previous_by_event_id.values.filter_map do |event|
      event['node_kernel_evidence_id']
    end)
    livepatches_by_evidence_id = livepatches_by_evidence(evidence_ids.uniq)

    candidates.filter_map do |event|
      previous = previous_by_event_id[event.fetch('id').to_i]
      next unless availability_only_event?(event, previous, livepatches_by_evidence_id)

      event.fetch('id').to_i
    end
  end

  def inactive_livepatch_event_candidates
    connection.select_all(<<~SQL.squish).to_a
      SELECT events.id,
             events.node_id,
             events.node_kernel_evidence_id,
             events.reported_release,
             events.observed_before
      FROM node_kernel_events AS events
      WHERE events.event_type = #{LIVEPATCH_CHANGE}
        AND events.source = #{NODE_REPORT_SOURCE}
        AND events.effective_at IS NULL
        AND events.node_kernel_evidence_id IS NOT NULL
        AND EXISTS (
          SELECT 1
          FROM node_kernel_livepatches AS livepatches
          WHERE livepatches.node_kernel_evidence_id = events.node_kernel_evidence_id
        )
        AND NOT EXISTS (
          SELECT 1
          FROM node_kernel_livepatches AS livepatches
          WHERE livepatches.node_kernel_evidence_id = events.node_kernel_evidence_id
            AND (
              livepatches.loaded = TRUE
              OR livepatches.enabled = TRUE
              OR livepatches.transition = TRUE
              OR livepatches.applied_at IS NOT NULL
            )
        )
      ORDER BY events.observed_before, events.id
      FOR UPDATE
    SQL
  end

  def previous_public_events(candidates)
    candidate_ids = candidates.to_h { |event| [event.fetch('id').to_i, true] }
    node_ids = candidates.map { |event| event.fetch('node_id').to_i }.uniq
    previous_by_event_id = {}
    latest_by_node_id = {}

    ordered_public_events(node_ids).each do |event|
      event_id = event.fetch('id').to_i
      node_id = event.fetch('node_id').to_i
      previous_by_event_id[event_id] = latest_by_node_id[node_id] if candidate_ids[event_id]
      latest_by_node_id[node_id] = event
    end

    previous_by_event_id
  end

  def ordered_public_events(node_ids)
    connection.select_all(<<~SQL.squish).to_a
      SELECT id, node_id, node_kernel_evidence_id, reported_release, observed_before
      FROM node_kernel_events
      WHERE node_id IN (#{quoted_ids(node_ids)})
        AND event_type IN (#{PUBLIC_EVENT_TYPES.join(', ')})
      ORDER BY node_id, observed_before, id
      FOR UPDATE
    SQL
  end

  def livepatches_by_evidence(evidence_ids)
    return {} if evidence_ids.empty?

    livepatches = connection.select_all(<<~SQL.squish).to_a
      SELECT node_kernel_evidence_id,
             livepatch_id,
             loaded,
             enabled,
             transition,
             applied_at
      FROM node_kernel_livepatches
      WHERE node_kernel_evidence_id IN (#{quoted_ids(evidence_ids)})
      ORDER BY node_kernel_evidence_id, livepatch_id
      FOR UPDATE
    SQL

    livepatches.group_by { |livepatch| livepatch.fetch('node_kernel_evidence_id').to_i }
  end

  def availability_only_event?(event, previous, livepatches_by_evidence_id)
    return false unless previous&.fetch('node_kernel_evidence_id', nil)
    return false unless previous.fetch('reported_release') == event.fetch('reported_release')

    current_livepatches = livepatches_by_evidence_id.fetch(
      event.fetch('node_kernel_evidence_id').to_i,
      []
    )
    previous_livepatches = livepatches_by_evidence_id.fetch(
      previous.fetch('node_kernel_evidence_id').to_i,
      []
    )

    return true unless previous_livepatches.any? { |livepatch| livepatch_active?(livepatch) }

    unavailable_successor?(current_livepatches, previous_livepatches)
  end

  def unavailable_successor?(current_livepatches, previous_livepatches)
    previous_effective_ids = previous_livepatches.filter_map do |livepatch|
      livepatch.fetch('livepatch_id') if livepatch_effective?(livepatch)
    end
    return false if previous_effective_ids.empty?

    current_ids = current_livepatches.map { |livepatch| livepatch.fetch('livepatch_id') }
    !previous_effective_ids.intersect?(current_ids)
  end

  def livepatch_active?(livepatch)
    database_true?(livepatch['loaded']) ||
      database_true?(livepatch['enabled']) ||
      database_true?(livepatch['transition']) ||
      livepatch['applied_at'].present?
  end

  def livepatch_effective?(livepatch)
    database_true?(livepatch['loaded']) &&
      database_true?(livepatch['enabled']) &&
      database_false?(livepatch['transition'])
  end

  def database_true?(value)
    value == true || value.to_s == '1'
  end

  def database_false?(value)
    value == false || value.to_s == '0'
  end

  def node_ids_for(event_ids)
    return [] if event_ids.empty?

    connection.select_values(<<~SQL.squish).map(&:to_i)
      SELECT DISTINCT node_id
      FROM node_kernel_events
      WHERE id IN (#{quoted_ids(event_ids)})
    SQL
  end

  def reclassify_inventory_events(event_ids)
    return if event_ids.empty?

    execute <<~SQL.squish
      UPDATE node_kernel_events
      SET event_type = #{LIVEPATCH_INVENTORY_CHANGE},
          livepatch_action = NULL,
          current = FALSE,
          updated_at = #{monotonic_updated_at_sql('updated_at')}
      WHERE id IN (#{quoted_ids(event_ids)})
    SQL
  end

  def backfill_applied_actions
    execute <<~SQL.squish
      UPDATE node_kernel_events AS events
      SET events.livepatch_action = #{APPLIED_ACTION},
          events.effective_at = NULL,
          events.confidence = #{INFERRED_CONFIDENCE},
          events.updated_at = #{monotonic_updated_at_sql('events.updated_at')}
      WHERE events.event_type = #{LIVEPATCH_CHANGE}
        AND events.effective_at IS NOT NULL
        AND EXISTS (
          SELECT 1
          FROM node_kernel_livepatches AS livepatches
          WHERE livepatches.node_kernel_evidence_id = events.node_kernel_evidence_id
            AND livepatches.loaded = TRUE
            AND livepatches.enabled = TRUE
            AND livepatches.transition = FALSE
            AND livepatches.applied_at IS NOT NULL
            AND livepatches.applied_at = events.effective_at
        )
    SQL
  end

  def repair_current_markers(node_ids)
    node_ids.each do |node_id|
      current_id = connection.select_value(<<~SQL.squish)&.to_i
        SELECT id
        FROM node_kernel_events
        WHERE node_id = #{connection.quote(node_id)}
          AND event_type IN (#{PUBLIC_EVENT_TYPES.join(', ')})
        ORDER BY observed_before DESC, id DESC
        LIMIT 1
      SQL

      execute <<~SQL.squish
        UPDATE node_kernel_events
        SET current = CASE WHEN id = #{connection.quote(current_id)} THEN TRUE ELSE FALSE END,
            updated_at = #{monotonic_updated_at_sql('updated_at')}
        WHERE node_id = #{connection.quote(node_id)}
          AND current != CASE WHEN id = #{connection.quote(current_id)} THEN TRUE ELSE FALSE END
      SQL
    end
  end

  def quoted_ids(ids)
    ids.map { |id| connection.quote(id) }.join(', ')
  end

  def monotonic_updated_at_sql(column)
    "GREATEST(CURRENT_TIMESTAMP(6), #{column} + INTERVAL 1 MICROSECOND)"
  end
end
