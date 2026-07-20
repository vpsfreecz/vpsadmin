require 'time'

class ReconcileReportedBootEvidence < ActiveRecord::Migration[8.1]
  BOOT_EVENT = 0
  RECONSTRUCTED_SOURCE = 0
  NODE_REPORT_SOURCE = 1
  INFERRED_CONFIDENCE = 1
  EXACT_CONFIDENCE = 2
  EVENT_SNAPSHOT = 1
  BOOT_TIME_TOLERANCE = 5.minutes

  def up
    transaction do
      # Bound every write to the exact population visible at the start. A boot
      # written later by an old supervisor must remain uncorrected so the new
      # supervisor performs its correction and duplicate deletion together.
      # The same set prevents a later no-op rerun from deleting a second nearby
      # reconstructed candidate.
      reported_ids = reported_boot_ids_needing_reconciliation
      next if reported_ids.empty?

      correct_reported_boot_effective_times(reported_ids)
      correct_reported_boot_confidence(reported_ids)
      delete_reconstructed_boot_duplicates(reported_ids)
    end
  end

  # These are corrections of derived history. A rollback keeps the
  # authoritative reported values and does not recreate reconstructed rows.
  def down; end

  protected

  def reported_boot_ids_needing_reconciliation
    connection.select_values(<<~SQL.squish).map(&:to_i)
      SELECT events.id
      FROM node_kernel_events AS events
      INNER JOIN node_kernel_evidences AS evidence
        ON evidence.id = events.node_kernel_evidence_id
      WHERE events.event_type = #{BOOT_EVENT}
        AND events.source = #{NODE_REPORT_SOURCE}
        AND evidence.snapshot_type = #{EVENT_SNAPSHOT}
        AND evidence.booted_at IS NOT NULL
        AND (
          events.effective_at IS NULL
          OR events.effective_at != evidence.booted_at
          OR events.confidence != #{expected_confidence_sql}
        )
      ORDER BY events.observed_before, events.id
      FOR UPDATE
    SQL
  end

  def correct_reported_boot_effective_times(reported_ids)
    execute <<~SQL.squish
      UPDATE node_kernel_events AS events
      INNER JOIN node_kernel_evidences AS evidence
        ON evidence.id = events.node_kernel_evidence_id
      SET events.effective_at = evidence.booted_at,
          events.updated_at = #{monotonic_updated_at_sql('events.updated_at')}
      WHERE events.event_type = #{BOOT_EVENT}
        AND events.id IN (#{quoted_ids(reported_ids)})
        AND events.source = #{NODE_REPORT_SOURCE}
        AND evidence.snapshot_type = #{EVENT_SNAPSHOT}
        AND evidence.booted_at IS NOT NULL
        AND (
          events.effective_at IS NULL
          OR events.effective_at != evidence.booted_at
        )
    SQL
  end

  def correct_reported_boot_confidence(reported_ids)
    execute <<~SQL.squish
      UPDATE node_kernel_events AS events
      INNER JOIN node_kernel_evidences AS evidence
        ON evidence.id = events.node_kernel_evidence_id
      SET events.confidence = #{expected_confidence_sql},
          events.updated_at = #{monotonic_updated_at_sql('events.updated_at')}
      WHERE events.event_type = #{BOOT_EVENT}
        AND events.id IN (#{quoted_ids(reported_ids)})
        AND events.source = #{NODE_REPORT_SOURCE}
        AND evidence.snapshot_type = #{EVENT_SNAPSHOT}
        AND evidence.booted_at IS NOT NULL
        AND events.confidence != #{expected_confidence_sql}
    SQL
  end

  def expected_confidence_sql
    <<~SQL.squish
      CASE WHEN EXISTS (
        SELECT 1
        FROM node_kernel_evidence_errors AS errors
        WHERE errors.node_kernel_evidence_id = evidence.id
          AND errors.component = 'booted_at'
          AND errors.reason = 'estimated_from_uptime'
      ) THEN #{INFERRED_CONFIDENCE} ELSE #{EXACT_CONFIDENCE} END
    SQL
  end

  def delete_reconstructed_boot_duplicates(reported_ids)
    return if reported_ids.empty?

    reconstructed_by_node = reconstructed_boots.group_by { |event| event.fetch('node_id') }
    used_reconstructed_ids = {}

    reported_boots(reported_ids).each do |reported|
      candidates = reconstructed_by_node.fetch(reported.fetch('node_id'), []).reject do |event|
        used_reconstructed_ids[event.fetch('id')]
      end
      reconstructed = matching_reconstructed_boot(reported, candidates)
      next unless reconstructed

      preserve_current_marker(reported, reconstructed)
      execute <<~SQL.squish
        DELETE FROM node_kernel_events
        WHERE id = #{connection.quote(reconstructed.fetch('id'))}
          AND source = #{RECONSTRUCTED_SOURCE}
      SQL
      used_reconstructed_ids[reconstructed.fetch('id')] = true
    end
  end

  def reported_boots(ids)
    connection.select_all(<<~SQL.squish).to_a
      SELECT events.id,
             events.node_id,
             COALESCE(events.booted_at, evidence.booted_at) AS booted_at,
             events.booted_release,
             events.observed_before,
             events.current
      FROM node_kernel_events AS events
      INNER JOIN node_kernel_evidences AS evidence
        ON evidence.id = events.node_kernel_evidence_id
      WHERE events.id IN (#{quoted_ids(ids)})
        AND events.event_type = #{BOOT_EVENT}
        AND events.source = #{NODE_REPORT_SOURCE}
        AND events.observed_after IS NULL
        AND evidence.snapshot_type = #{EVENT_SNAPSHOT}
        AND COALESCE(events.booted_at, evidence.booted_at) IS NOT NULL
        AND events.booted_release IS NOT NULL
      ORDER BY events.observed_before, events.id
    SQL
  end

  def reconstructed_boots
    connection.select_all(<<~SQL.squish).to_a
      SELECT id, node_id, booted_at, booted_release, observed_before, current
      FROM node_kernel_events
      WHERE event_type = #{BOOT_EVENT}
        AND source = #{RECONSTRUCTED_SOURCE}
        AND booted_at IS NOT NULL
        AND booted_release IS NOT NULL
      ORDER BY observed_before, id
    SQL
  end

  def quoted_ids(ids)
    ids.map { |id| connection.quote(id) }.join(', ')
  end

  def matching_reconstructed_boot(reported, candidates)
    reported_booted_at = parse_time(reported.fetch('booted_at'))
    reported_observed_before = parse_time(reported.fetch('observed_before'))

    candidates.filter_map do |candidate|
      next unless candidate.fetch('booted_release') == reported.fetch('booted_release')
      next if parse_time(candidate.fetch('observed_before')) > reported_observed_before

      difference = (parse_time(candidate.fetch('booted_at')) - reported_booted_at).abs
      next if difference > BOOT_TIME_TOLERANCE

      [difference, -parse_time(candidate.fetch('observed_before')).to_f, -candidate.fetch('id'), candidate]
    end.min_by { |match| match.first(3) }&.last
  end

  def preserve_current_marker(reported, reconstructed)
    return unless reconstructed.fetch('current').to_i == 1

    another_current = connection.select_value(<<~SQL.squish)
      SELECT 1
      FROM node_kernel_events
      WHERE node_id = #{connection.quote(reconstructed.fetch('node_id'))}
        AND current = TRUE
        AND id != #{connection.quote(reconstructed.fetch('id'))}
      LIMIT 1
    SQL
    return if another_current

    execute <<~SQL.squish
      UPDATE node_kernel_events
      SET current = TRUE,
          updated_at = #{monotonic_updated_at_sql('updated_at')}
      WHERE id = #{connection.quote(reported.fetch('id'))}
        AND current = FALSE
    SQL
  end

  def parse_time(value)
    return value.to_time if value.respond_to?(:to_time)

    Time.iso8601(value.to_s)
  end

  def monotonic_updated_at_sql(column)
    "GREATEST(CURRENT_TIMESTAMP(6), #{column} + INTERVAL 1 MICROSECOND)"
  end
end
