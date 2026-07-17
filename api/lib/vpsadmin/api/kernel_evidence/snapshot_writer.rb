require 'time'

module VpsAdmin::API::KernelEvidence
  class SnapshotWriter
    def self.call(snapshot:, report:, observed_at:, received_at:)
      new(snapshot:, report:, observed_at:, received_at:).call
    end

    def initialize(snapshot:, report:, observed_at:, received_at:)
      @snapshot = snapshot
      @report = report
      @observed_at = observed_at
      @received_at = received_at
    end

    def call
      if @snapshot.persisted? && @snapshot.event?
        raise ActiveRecord::ReadOnlyRecord, 'event evidence snapshots are immutable'
      end

      ::NodeKernelEvidence.transaction do
        assign_snapshot
        reconcile_kernel_parameters
        reconcile_named(
          @snapshot.kernel_modules,
          @report.loaded_modules.to_h { |name| [name, {}] }
        )
        reconcile_sysctls
        reconcile_software_versions
        reconcile_livepatches
        reconcile_ebpf_programs
        reconcile_errors
      end
      @snapshot
    end

    protected

    def assign_snapshot
      kernel = @report.kernel
      deployment = @report.deployment
      @snapshot.assign_attributes(
        report_schema_version: @report.schema_version,
        observed_at: @observed_at,
        received_at: @received_at,
        snapshot_revision: @report.digest,
        boot_id: kernel.boot_id,
        booted_at: parse_time(kernel.booted_at),
        booted_release: kernel.booted_release,
        reported_release: kernel.reported_release,
        kernel_source_revision: kernel.source_revision,
        kernel_config_digest: kernel.config_digest,
        kernel_command_line: kernel.command_line,
        booted_system: deployment.booted_system,
        current_system: deployment.current_system
      )
      @snapshot.save!
    end

    def reconcile_kernel_parameters
      desired = @report.kernel.booted_parameters.each_with_index.map do |token, position|
        name, value = token.split('=', 2)
        [position, name, value]
      end
      current = @snapshot.kernel_parameters.order(:position).pluck(:position, :name, :value)
      return if desired == current

      @snapshot.kernel_parameters.delete_all
      desired.each do |position, name, value|
        @snapshot.kernel_parameters.create!(position:, name:, value:)
      end
    end

    def reconcile_named(relation, desired)
      existing = relation.index_by(&:name)
      relation.where.not(name: desired.keys).delete_all
      desired.each do |name, attrs|
        record = existing[name] || relation.build(name:)
        record.assign_attributes(attrs)
        record.save! if record.new_record? || record.changed?
      end
    end

    def reconcile_sysctls
      desired = @report.sysctls.to_h do |name, sysctl|
        [
          name,
          {
            available: sysctl.available,
            configured_value: sysctl.configured,
            effective_value: sysctl.effective
          }
        ]
      end
      reconcile_named(@snapshot.sysctls, desired)
    end

    def reconcile_software_versions
      desired = @report.software_versions.to_h do |software|
        [
          software.key,
          {
            generation: software.generation,
            component: software.component,
            version: software.version,
            version_source: software.version_source,
            revision: software.revision,
            revision_source: software.revision_source,
            revision_dirty: software.revision_dirty
          }
        ]
      end
      existing = @snapshot.software_versions.index_by do |software|
        [software.generation, software.component]
      end
      @snapshot.software_versions.where.not(
        id: existing.values_at(*desired.keys).compact.map(&:id)
      ).delete_all
      desired.each do |key, attrs|
        record = existing[key] || @snapshot.software_versions.build
        record.assign_attributes(attrs)
        record.save! if record.new_record? || record.changed?
      end
    end

    def reconcile_livepatches
      desired = @report.livepatches.to_h { |livepatch| [livepatch.id, livepatch] }
      @snapshot.kernel_livepatches.where.not(livepatch_id: desired.keys).destroy_all
      existing = @snapshot.kernel_livepatches.index_by(&:livepatch_id)
      desired.each do |id, source|
        livepatch = existing[id] || @snapshot.kernel_livepatches.build(livepatch_id: id)
        livepatch.assign_attributes(
          kernel_version: source.kernel_version,
          patch_version: source.patch_version,
          loaded: source.loaded,
          enabled: source.enabled,
          transition: source.transition,
          applied_at: parse_time(source.applied_at),
          verified_at: parse_time(source.verified_at)
        )
        livepatch.save! if livepatch.new_record? || livepatch.changed?
        reconcile_livepatch_patches(livepatch, source.patches)
      end
    end

    def reconcile_livepatch_patches(livepatch, source_patches)
      desired = source_patches.to_h { |patch| [patch.name, patch.version] }
      livepatch.patches.where.not(name: desired.keys).delete_all
      existing = livepatch.patches.index_by(&:name)
      desired.each do |name, version|
        patch = existing[name] || livepatch.patches.build(name:)
        patch.version = version
        patch.save! if patch.new_record? || patch.changed?
      end
    end

    def reconcile_ebpf_programs
      desired = @report.ebpf_programs.to_h { |program| [program.name, program] }
      @snapshot.ebpf_programs.where.not(name: desired.keys).destroy_all
      existing = @snapshot.ebpf_programs.index_by(&:name)
      desired.each do |name, source|
        program = existing[name] || @snapshot.ebpf_programs.build(name:)
        program.assign_attributes(
          description: source.description,
          since_kernel: source.since_kernel,
          until_kernel: source.until_kernel,
          revision: source.revision,
          digest: source.digest,
          active: source.active,
          attached_at: parse_time(source.attached_at),
          verified_at: parse_time(source.verified_at)
        )
        program.save! if program.new_record? || program.changed?
        reconcile_ebpf_objects(program, source.objects)
        reconcile_ebpf_links(program, source.links)
      end
    end

    def reconcile_ebpf_objects(program, names)
      program.program_objects.where.not(name: names).delete_all
      existing = program.program_objects.pluck(:name)
      (names - existing).each { |name| program.program_objects.create!(name:) }
    end

    def reconcile_ebpf_links(program, links)
      program.program_links.where.not(name: links.keys).delete_all
      existing = program.program_links.index_by(&:name)
      links.each do |name, attached|
        link = existing[name] || program.program_links.build(name:)
        link.attached = attached
        link.save! if link.new_record? || link.changed?
      end
    end

    def reconcile_errors
      desired = @report.errors.map { |error| [error.component, error.reason] }
      current = @snapshot.kernel_evidence_errors.order(:id).pluck(:component, :reason)
      return if desired == current

      @snapshot.kernel_evidence_errors.delete_all
      desired.each do |component, reason|
        @snapshot.kernel_evidence_errors.create!(component:, reason:)
      end
    end

    def parse_time(value)
      return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
      return if value.nil?

      Time.iso8601(value)
    end
  end
end
