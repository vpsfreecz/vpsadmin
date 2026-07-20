require 'vpsadmin/api/operations/base'
require 'vpsadmin/api/operations/node/history_backfill'

module VpsAdmin::API
  class Operations::Node::ReconstructKernelEvents < Operations::Base
    include Operations::Node::HistoryBackfill

    BOOT_TIME_TOLERANCE = 5.minutes
    MAX_STATUS_GAP = 30.minutes

    Candidate = Data.define(:status_watermark, :exact_boundary, :status_ids)
    StatusSample = Data.define(:id, :observed_at, :uptime, :kernel)
    HistoryGap = Data.define(:from, :to, :reason)
    Reconstruction = Data.define(:first_status, :last_status, :events, :gaps)

    # Historical samples are immutable. Select their ordered IDs once, compute
    # without the Node lock, then verify the append watermark and exact-history
    # boundary while holding the short write lock.
    #
    # @param node [::Node]
    # @param batch_size [Integer]
    # @param force [Boolean]
    # @param progress [VpsAdmin::API::Tasks::ProgressReporter, nil]
    # @return [Integer] number of reconstructed events created
    def run(
      node,
      batch_size: DEFAULT_BATCH_SIZE,
      force: false,
      progress: nil
    )
      return 0 unless node.node? || node.storage?
      return 0 if !force && ::NodeKernelHistoryState.exists?(node_id: node.id)

      batch_size = validate_batch_size(batch_size)
      retries = 0

      loop do
        candidate = capture_candidate(node)
        progress&.start(total: candidate.status_ids.length, attempt: retries + 1)
        reconstruction = scan(candidate, batch_size, progress)
        created = commit(node, candidate, reconstruction, force:)

        unless created.equal?(RETRY)
          progress&.finish(created:)
          return created
        end

        retries = retry_scan!(
          progress,
          retries,
          'status watermark or exact kernel-history boundary changed'
        )
      end
    end

    protected

    def capture_candidate(node)
      watermark = status_watermark(node)
      boundary = exact_boundary(node)
      Candidate.new(
        status_watermark: watermark,
        exact_boundary: boundary,
        status_ids: ordered_status_ids(
          node,
          watermark:,
          before: boundary&.last
        )
      )
    end

    def exact_boundary(node)
      ::NodeKernelEvent.kernel_history
                       .node_report
                       .where(node_id: node.id)
                       .order(:observed_before, :id)
                       .limit(1)
                       .pluck(:id, :observed_before)
                       .first
    end

    def scan(candidate, batch_size, progress)
      first_status = nil
      last_status = nil
      previous_status = nil
      booted_at = nil
      booted_release = nil
      events = []
      gaps = []
      processed = 0

      each_status_batch(
        candidate.status_ids,
        %i[created_at uptime kernel],
        batch_size
      ) do |rows|
        rows.each do |id, observed_at, uptime, kernel|
          status = StatusSample.new(id:, observed_at:, uptime:, kernel:)
          first_status ||= status

          if previous_status && observed_at - previous_status.observed_at > MAX_STATUS_GAP
            gaps << HistoryGap.new(
              from: previous_status.observed_at,
              to: observed_at,
              reason: 'node status sampling gap'
            )
          end

          estimated_boot = observed_at - uptime
          if new_boot?(previous_status, booted_at, status, estimated_boot)
            booted_at = estimated_boot
            booted_release = kernel
            events << event_attributes(
              event_type: :boot,
              status:,
              booted_at:,
              booted_release:,
              observed_after: previous_status&.observed_at,
              effective_at: booted_at
            )
          elsif previous_status.kernel != kernel
            events << event_attributes(
              event_type: :reported_release_change,
              status:,
              booted_at:,
              booted_release:,
              observed_after: previous_status.observed_at
            )
          end

          previous_status = status
          last_status = status
        end

        processed += rows.length
        progress&.advance(processed:, created: events.length)
      end

      Reconstruction.new(first_status:, last_status:, events:, gaps:)
    end

    def new_boot?(previous_status, booted_at, status, estimated_boot)
      return true unless previous_status && booted_at
      return true if status.uptime < previous_status.uptime

      (estimated_boot - booted_at).abs > BOOT_TIME_TOLERANCE
    end

    def event_attributes(
      event_type:,
      status:,
      booted_at:,
      booted_release:,
      observed_after:,
      effective_at: nil
    )
      {
        source_status_id: status.id,
        event_type:,
        source: :reconstructed_node_status,
        confidence: :inferred,
        booted_at:,
        booted_release:,
        reported_release: status.kernel,
        effective_at:,
        observed_after:,
        observed_before: status.observed_at
      }
    end

    def commit(node, candidate, reconstruction, force:)
      node.with_lock(requires_new: true) do
        if status_watermark(node) != candidate.status_watermark ||
           exact_boundary(node) != candidate.exact_boundary
          next RETRY
        end

        state = ::NodeKernelHistoryState.find_or_initialize_by(node:)
        next 0 if state.persisted? && !force

        events = reject_reported_bootstrap_duplicate(node, reconstruction.events)
        created = create_events(node, events)
        state.assign_attributes(
          from_status_id: reconstruction.first_status&.id,
          through_status_id: reconstruction.last_status&.id,
          started_at: reconstruction.first_status&.observed_at,
          observed_through: reconstruction.last_status&.observed_at,
          completed_at: Time.current
        )
        state.save!
        replace_gaps(state, reconstruction.gaps)
        mark_current_kernel_event(node)
        created
      end
    end

    def create_events(node, events)
      events.sum do |attributes|
        event = ::NodeKernelEvent.find_or_initialize_by(
          node:,
          source: :reconstructed_node_status,
          source_status_id: attributes[:source_status_id],
          event_type: attributes[:event_type]
        )
        next 0 if event.persisted?

        event.assign_attributes(attributes)
        event.save!
        1
      end
    end

    # A forced backfill may scan the legacy samples that originally produced a
    # bootstrap row which has since been replaced by exact reported evidence.
    # Do not recreate that one derived duplicate.
    def reject_reported_bootstrap_duplicate(node, events)
      reported = node.node_kernel_events.node_report.boot
                     .where(observed_after: nil)
                     .order(:observed_before, :id)
                     .first
      reported_booted_at = reported&.booted_at || reported&.effective_at
      return events unless reported_booted_at && reported.booted_release

      duplicate_index = events.each_index.filter_map do |index|
        event = events[index]
        next unless event[:event_type] == :boot
        next unless event[:booted_release] == reported.booted_release
        next if event[:observed_before] > reported.observed_before

        difference = (event[:booted_at] - reported_booted_at).abs
        next if difference > BOOT_TIME_TOLERANCE

        [difference, -event[:observed_before].to_f, -event[:source_status_id], index]
      end.min_by { |candidate| candidate.first(3) }&.last
      return events unless duplicate_index

      events.each_with_index.filter_map { |event, index| event unless index == duplicate_index }
    end

    def mark_current_kernel_event(node)
      events = node.node_kernel_events.kernel_history
      events.update_all(current: false)
      current = events.node_report.order(observed_before: :desc, id: :desc).first
      current ||= events.order(observed_before: :desc, id: :desc).first
      current&.update!(current: true)
    end

    def replace_gaps(state, gaps)
      state.kernel_history_gaps.delete_all
      gaps.each do |gap|
        state.kernel_history_gaps.create!(from: gap.from, to: gap.to, reason: gap.reason)
      end
    end
  end
end
