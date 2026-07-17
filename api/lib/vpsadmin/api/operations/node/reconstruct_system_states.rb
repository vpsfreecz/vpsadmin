require 'vpsadmin/api/operations/base'
require 'vpsadmin/api/operations/node/history_backfill'

module VpsAdmin::API
  class Operations::Node::ReconstructSystemStates < Operations::Base
    include Operations::Node::HistoryBackfill

    Candidate = Data.define(
      :status_watermark,
      :live_boundary,
      :current_status,
      :status_ids
    )
    StatusSample = Data.define(:id, :observed_at, :values)
    Reconstruction = Data.define(
      :first_status,
      :last_status,
      :started_at,
      :observed_through,
      :states
    )

    # @param node [::Node]
    # @param batch_size [Integer]
    # @param force [Boolean]
    # @param progress [VpsAdmin::API::Tasks::ProgressReporter, nil]
    # @return [Integer] number of reconstructed states created
    def run(
      node,
      batch_size: DEFAULT_BATCH_SIZE,
      force: false,
      progress: nil
    )
      return 0 unless node.system_state_host?
      return 0 if !force && ::NodeSystemHistoryState.exists?(node_id: node.id)

      batch_size = validate_batch_size(batch_size)
      retries = 0

      loop do
        checkpoint = ::NodeSystemHistoryState.find_by(node_id: node.id)
        candidate = capture_candidate(node, checkpoint:, force:)
        total = candidate.status_ids.length + (candidate.current_status ? 1 : 0)
        progress&.start(total:, attempt: retries + 1)
        reconstruction = scan(candidate, batch_size, progress)
        created = commit(node, candidate, reconstruction, checkpoint:, force:)

        unless created.equal?(RETRY)
          progress&.finish(created:)
          return created
        end

        retries = retry_scan!(
          progress,
          retries,
          'status watermark or live system-state boundary changed'
        )
      end
    end

    protected

    def capture_candidate(node, checkpoint:, force:)
      watermark = status_watermark(node)
      boundary = live_boundary(node, checkpoint:, force:)
      current = boundary ? nil : current_status_sample(node)
      Candidate.new(
        status_watermark: watermark,
        live_boundary: boundary,
        current_status: current,
        status_ids: ordered_status_ids(
          node,
          watermark:,
          before: boundary&.last
        )
      )
    end

    def live_boundary(node, checkpoint:, force:)
      scope = ::NodeSystemState.where(node_id: node.id)
                               .order(:first_observed_at, :id)
      if force && checkpoint&.observed_through
        scope = scope.where('last_observed_at > ?', checkpoint.observed_through)
      end

      scope.limit(1).pluck(:id, :first_observed_at).first
    end

    def current_status_sample(node)
      row = ::NodeCurrentStatus.where(node_id: node.id).limit(1).pluck(
        :id,
        :created_at,
        :updated_at,
        :cpus,
        :total_memory,
        :total_swap,
        :cgroup_version
      ).first
      return unless row

      id, created_at, updated_at, cpus, memory, swap, cgroup = row
      observed_at = updated_at || created_at
      return unless observed_at

      StatusSample.new(
        id:,
        observed_at:,
        values: normalize(cpus, memory, swap, cgroup)
      )
    end

    def scan(candidate, batch_size, progress)
      states = []
      first_status = nil
      last_status = nil
      started_at = nil
      observed_through = nil
      processed = 0

      each_status_batch(
        candidate.status_ids,
        %i[created_at cpus total_memory total_swap cgroup_version],
        batch_size
      ) do |rows|
        rows.each do |id, observed_at, cpus, memory, swap, cgroup|
          sample = StatusSample.new(
            id:,
            observed_at:,
            values: normalize(cpus, memory, swap, cgroup)
          )
          first_status ||= sample
          last_status = sample
          started_at ||= observed_at
          observed_through = observed_at
          append_state(states, sample)
        end

        processed += rows.length
        progress&.advance(processed:, created: states.length)
      end

      if candidate.current_status
        sample = candidate.current_status
        started_at ||= sample.observed_at
        observed_through = sample.observed_at
        append_state(states, sample)
        processed += 1
        progress&.advance(processed:, created: states.length)
      end

      Reconstruction.new(
        first_status:,
        last_status:,
        started_at:,
        observed_through:,
        states:
      )
    end

    def normalize(cpus, memory, swap, cgroup)
      VpsAdmin::API::SystemState::Normalizer.from_values(
        cpus:,
        total_memory: memory,
        total_swap: swap,
        cgroup_version: cgroup
      )
    end

    def append_state(states, sample)
      if states.any? && same_values?(states.last, sample.values)
        states.last[:last_observed_at] = sample.observed_at
      else
        states << sample.values.merge(
          first_observed_at: sample.observed_at,
          last_observed_at: sample.observed_at
        )
      end
    end

    def commit(node, candidate, reconstruction, checkpoint:, force:)
      node.with_lock(requires_new: true) do
        current_checkpoint = ::NodeSystemHistoryState.find_by(node_id: node.id)
        current_boundary = live_boundary(node, checkpoint: current_checkpoint, force:)
        current_status = current_boundary ? nil : current_status_sample(node)
        if status_watermark(node) != candidate.status_watermark ||
           current_boundary != candidate.live_boundary ||
           current_status != candidate.current_status
          next RETRY
        end
        next 0 if current_checkpoint && !force

        remove_previous_reconstruction(node, candidate) if force && checkpoint
        created = reconcile_states(node, reconstruction.states)
        state = current_checkpoint || ::NodeSystemHistoryState.new(node:)
        state.assign_attributes(
          from_status_id: reconstruction.first_status&.id,
          through_status_id: reconstruction.last_status&.id,
          started_at: reconstruction.started_at,
          observed_through: reconstruction.observed_through,
          completed_at: Time.current
        )
        state.save!
        created
      end
    end

    def remove_previous_reconstruction(node, candidate)
      states = node.node_system_states.order(:first_observed_at, :id).to_a
      live_index = if candidate.live_boundary
                     states.index { |state| state.id == candidate.live_boundary.first }
                   end
      reconstructed = live_index ? states.take(live_index) : states
      reconstructed.each(&:destroy!)
    end

    def reconcile_states(node, states)
      existing = node.node_system_states.order(:first_observed_at, :id).to_a
      attrs = states.map(&:dup)

      if existing.any? && attrs.any? && same_values?(attrs.last, existing.first.attributes.symbolize_keys)
        first = existing.first
        first.update!(first_observed_at: attrs.last[:first_observed_at])
        attrs.pop
      end

      attrs.each_with_index do |state_attrs, index|
        node.node_system_states.create!(
          state_attrs.merge(current: existing.empty? && index == attrs.length - 1)
        )
      end
      attrs.length
    end

    def same_values?(left, right)
      VpsAdmin::API::SystemState::Normalizer.same?(left, right)
    end
  end
end
