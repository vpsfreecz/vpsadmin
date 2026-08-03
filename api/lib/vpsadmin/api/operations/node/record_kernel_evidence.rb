require 'time'
require 'vpsadmin/api/kernel_evidence/boot_time_confidence'
require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::Node::RecordKernelEvidence < Operations::Base
    event_policy :resource,
                 models: [
                   ::NodeKernelEvent,
                   ::NodeKernelEvidence,
                   ::NodeSoftwareChange,
                   ::NodeSysctlChange
                 ]
    BOOT_TIME_TOLERANCE = 5.minutes

    def run(
      node:,
      observed_at:,
      report:,
      received_at: observed_at,
      previous_report: nil,
      previous_observed_at: nil
    )
      @event_snapshot = nil
      @received_at = received_at

      node.with_lock do
        if new_boot?(report, previous_report)
          booted_at = parse_time(report.kernel.booted_at)
          event = create_event!(
            node:,
            event_type: :boot,
            observed_at:,
            previous_observed_at:,
            report:,
            effective_at: booted_at,
            confidence: VpsAdmin::API::KernelEvidence::BootTimeConfidence.from_report(report)
          )
          delete_reconstructed_boot_duplicate!(node, event)
          record_sysctl_changes(event, report, previous_report)
          record_software_changes(event, report, previous_report)
          return
        end

        record_kernel_release_changes(
          node:,
          report:,
          previous_report:,
          observed_at:,
          previous_observed_at:
        )
        record_runtime_changes(
          node:,
          report:,
          previous_report:,
          observed_at:,
          previous_observed_at:
        )
        record_sysctl_event(
          node:,
          report:,
          previous_report:,
          observed_at:,
          previous_observed_at:
        )
        record_deployment_event(
          node:,
          report:,
          previous_report:,
          observed_at:,
          previous_observed_at:
        )
      end
    end

    protected

    def new_boot?(report, previous_report)
      return true unless previous_report

      kernel = report.kernel
      previous = previous_report.kernel
      if kernel.boot_id && previous.boot_id
        kernel.boot_id != previous.boot_id
      else
        kernel.booted_at != previous.booted_at
      end
    end

    def record_kernel_release_changes(
      node:,
      report:,
      previous_report:,
      observed_at:,
      previous_observed_at:
    )
      return unless livepatch_observation_complete?(report)

      livepatch_changed = report.livepatches != previous_report.livepatches
      stable_event = stable_kernel_event(node)
      stable_report = VpsAdmin::API::KernelEvidence::SnapshotReader.call(
        stable_event&.kernel_evidence
      ) || previous_report
      stable_observed_at = stable_event&.observed_before || previous_observed_at
      release_changed = report.kernel.reported_release != stable_report.kernel.reported_release
      lifecycle = livepatch_lifecycle(stable_report, report)

      if lifecycle
        lifecycle_observed_after = stable_observed_at
        if lifecycle == :applied && livepatch_observation_complete?(previous_report)
          lifecycle_observed_after = previous_observed_at
        end
        create_event!(
          node:,
          event_type: :livepatch_change,
          livepatch_action: lifecycle,
          observed_at:,
          previous_observed_at: lifecycle_observed_after,
          report:
        )
        return
      end

      if release_changed && !livepatch_transitioning?(report.livepatches)
        create_event!(
          node:,
          event_type: :reported_release_change,
          observed_at:,
          previous_observed_at: stable_observed_at,
          report:
        )
        return
      end

      return unless livepatch_changed || release_changed

      create_event!(
        node:,
        event_type: :livepatch_inventory_change,
        observed_at:,
        previous_observed_at:,
        report:,
        public_event: false
      )
    end

    def record_runtime_changes(
      node:,
      report:,
      previous_report:,
      observed_at:,
      previous_observed_at:
    )
      ebpf_effective_at = newly_applied_at(
        report.ebpf_programs,
        previous_report.ebpf_programs,
        identity: :name,
        timestamp: :attached_at
      )
      if report.ebpf_programs.map(&:change_state) != previous_report.ebpf_programs.map(&:change_state)
        create_event!(
          node:,
          event_type: :ebpf_change,
          observed_at:,
          previous_observed_at:,
          report:,
          effective_at: ebpf_effective_at,
          confidence: ebpf_effective_at ? :exact : :inferred,
          public_event: false
        )
      end

      return if report.loaded_modules == previous_report.loaded_modules

      create_event!(
        node:,
        event_type: :module_change,
        observed_at:,
        previous_observed_at:,
        report:,
        public_event: false
      )
    end

    def record_sysctl_event(
      node:,
      report:,
      previous_report:,
      observed_at:,
      previous_observed_at:
    )
      changed = report.sysctls != previous_report.sysctls
      event = if changed
                create_event!(
                  node:,
                  event_type: :sysctl_change,
                  observed_at:,
                  previous_observed_at:,
                  report:,
                  public_event: false
                )
              end
      record_sysctl_changes(event, report, previous_report)
    end

    def record_deployment_event(
      node:,
      report:,
      previous_report:,
      observed_at:,
      previous_observed_at:
    )
      changed = report.deployment != previous_report.deployment ||
                report.software_versions != previous_report.software_versions
      return unless changed

      event = create_event!(
        node:,
        event_type: :deployment_change,
        observed_at:,
        previous_observed_at:,
        report:,
        public_event: false
      )
      record_software_changes(event, report, previous_report)
    end

    def record_sysctl_changes(event, report, previous_report)
      return unless event

      current = report.sysctls
      previous = previous_report&.sysctls || {}
      (current.keys | previous.keys).sort.each do |name|
        before = previous[name]
        after = current[name]
        next if before == after

        event.sysctl_changes.create!(
          name:,
          before_available: before&.available,
          before_configured_value: before&.configured,
          before_effective_value: before&.effective,
          after_available: after&.available,
          after_configured_value: after&.configured,
          after_effective_value: after&.effective
        )
      end
    end

    def record_software_changes(event, report, previous_report)
      current = report.software_versions.to_h { |version| [version.key, version] }
      previous = (previous_report&.software_versions || []).to_h do |version|
        [version.key, version]
      end
      (current.keys | previous.keys).sort.each do |generation, component|
        before = previous[[generation, component]]
        after = current[[generation, component]]
        next if before == after

        event.software_changes.create!(
          generation:,
          component:,
          before_version: before&.version,
          before_version_source: before&.version_source,
          before_revision: before&.revision,
          before_revision_source: before&.revision_source,
          before_revision_dirty: before&.revision_dirty || false,
          after_version: after&.version,
          after_version_source: after&.version_source,
          after_revision: after&.revision,
          after_revision_source: after&.revision_source,
          after_revision_dirty: after&.revision_dirty || false
        )
      end
    end

    def newly_applied_at(current, previous, identity:, timestamp:)
      previous_by_id = previous.to_h { |item| [item.public_send(identity), item] }
      current.filter_map do |item|
        before = previous_by_id[item.public_send(identity)]
        value = item.public_send(timestamp)
        next if before && before.public_send(timestamp) == value

        parse_time(value)
      end.max
    end

    def stable_kernel_event(node)
      node.node_kernel_events.kernel_history
          .where(current: true)
          .where.not(node_kernel_evidence_id: nil)
          .includes(kernel_evidence: { kernel_livepatches: :patches })
          .order(observed_before: :desc, id: :desc)
          .first
    end

    def livepatch_lifecycle(previous_report, current_report)
      current = current_report.livepatches
      return unless livepatch_observation_complete?(previous_report)
      return unless livepatch_observation_complete?(current_report)
      return if livepatch_transitioning?(current)

      previous_effective = effective_livepatches(previous_report.livepatches)
      current_effective = effective_livepatches(current)
      added_ids = current_effective.keys - previous_effective.keys
      removed_ids = previous_effective.keys - current_effective.keys

      return :applied if added_ids.any?
      return :removed if removal_observed?(
        removed_ids,
        current,
        previous_report.kernel.reported_release,
        current_report.kernel.reported_release
      )

      nil
    end

    def removal_observed?(removed_ids, current, previous_release, current_release)
      return false if removed_ids.empty?
      return true if current.empty? || current_release != previous_release

      current_ids = current.map(&:id)
      removed_ids.any? { |id| current_ids.include?(id) }
    end

    def effective_livepatches(livepatches)
      livepatches.select do |livepatch|
        livepatch.loaded &&
          livepatch.enabled &&
          livepatch.transition == false
      end.to_h { |livepatch| [livepatch.id, livepatch] }
    end

    def livepatch_transitioning?(livepatches)
      livepatches.any?(&:transition)
    end

    def livepatch_observation_complete?(report)
      return false if report.livepatches.any? do |livepatch|
        [livepatch.loaded, livepatch.enabled, livepatch.transition].any?(&:nil?)
      end

      report.errors.none? do |error|
        error.component == 'livepatches' ||
          error.component.match?(/\Alivepatch\..+\.(?:enabled|transition)\z/)
      end
    end

    def delete_reconstructed_boot_duplicate!(node, reported_event)
      return unless reported_event.observed_after.nil?

      reported_booted_at = reported_event.booted_at || reported_event.effective_at
      return unless reported_booted_at && reported_event.booted_release

      candidates = node.node_kernel_events.reconstructed_node_status.boot
                       .where(booted_release: reported_event.booted_release)
                       .where(
                         booted_at: (
                           (reported_booted_at - BOOT_TIME_TOLERANCE)..
                           (reported_booted_at + BOOT_TIME_TOLERANCE)
                         )
                       )
                       .where('observed_before <= ?', reported_event.observed_before)
                       .to_a
      reconstructed = candidates.min_by do |candidate|
        [
          (candidate.booted_at - reported_booted_at).abs,
          -candidate.observed_before.to_f,
          -candidate.id
        ]
      end
      return unless reconstructed

      if reconstructed.current? && !reported_event.current? &&
         !node.node_kernel_events.where(current: true).where.not(id: reconstructed.id).exists?
        reported_event.update!(current: true)
      end
      reconstructed.destroy!
    end

    def create_event!(
      node:,
      event_type:,
      observed_at:,
      previous_observed_at:,
      report:,
      livepatch_action: nil,
      effective_at: nil,
      confidence: :inferred,
      public_event: true
    )
      if public_event
        previous = node.node_kernel_events.kernel_history.where(current: true).to_a
        ::NodeKernelEvent.where(id: previous.map(&:id)).update_all(current: false)
        VpsAdmin::API::Events::ActionPolicies.record_many(
          :updated,
          previous,
          changed_fields: %i[current]
        )
      end
      kernel = report.kernel
      ::NodeKernelEvent.create!(
        node:,
        event_type:,
        livepatch_action:,
        source: :node_report,
        confidence:,
        boot_id: kernel.boot_id,
        booted_at: parse_time(kernel.booted_at),
        booted_release: kernel.booted_release,
        reported_release: kernel.reported_release,
        effective_at:,
        observed_after: previous_observed_at,
        observed_before: observed_at,
        current: public_event,
        kernel_evidence: event_snapshot(node, report, observed_at)
      )
    end

    def event_snapshot(node, report, observed_at)
      @event_snapshot ||= ::NodeKernelEvidence.new(
        node:,
        snapshot_type: :event
      ).tap do |snapshot|
        VpsAdmin::API::KernelEvidence::SnapshotWriter.call(
          snapshot:,
          report:,
          observed_at:,
          received_at: @received_at
        )
      end
    end

    def parse_time(value)
      return value if value.is_a?(Time)
      return if value.nil?

      Time.iso8601(value)
    end
  end
end
