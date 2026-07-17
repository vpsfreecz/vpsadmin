module VpsAdmin::API::KernelEvidence
  class SnapshotReader
    Comparison = Data.define(:report, :observed_at)

    def self.call(snapshot) = snapshot && new(snapshot).call

    def self.comparison(node:, current_snapshot:)
      current_report = call(current_snapshot)
      if comparable?(current_report)
        return Comparison.new(
          report: current_report,
          observed_at: current_snapshot.observed_at
        )
      end

      event = node.node_kernel_events.node_report
                  .where.not(node_kernel_evidence_id: nil)
                  .order(observed_before: :desc, id: :desc)
                  .first
      Comparison.new(
        report: call(event&.kernel_evidence),
        observed_at: event&.observed_before
      )
    end

    def self.comparable?(report)
      report &&
        report.kernel.booted_release.is_a?(String) &&
        report.kernel.reported_release.is_a?(String)
    end

    private_class_method :comparable?

    def initialize(snapshot)
      @snapshot = snapshot
    end

    def call
      Report.from_hash(
        'schema_version' => @snapshot.report_schema_version,
        'kernel' => kernel,
        'livepatches' => livepatches,
        'ebpf_programs' => ebpf_programs,
        'deployment' => {
          'booted_system' => @snapshot.booted_system,
          'current_system' => @snapshot.current_system
        },
        'software_versions' => software_versions,
        'loaded_modules' => @snapshot.kernel_modules.order(:name).pluck(:name),
        'sysctls' => sysctls,
        'errors' => @snapshot.kernel_evidence_errors.order(:id).map do |error|
          { 'component' => error.component, 'reason' => error.reason }
        end
      )
    end

    protected

    def kernel
      {
        'boot_id' => @snapshot.boot_id,
        'booted_at' => iso8601(@snapshot.booted_at),
        'booted_release' => @snapshot.booted_release,
        'reported_release' => @snapshot.reported_release,
        'kernel_source_revision' => @snapshot.kernel_source_revision,
        'config_digest' => @snapshot.kernel_config_digest,
        'booted_params' => @snapshot.kernel_parameters.order(:position).map do |parameter|
          parameter.value.nil? ? parameter.name : "#{parameter.name}=#{parameter.value}"
        end,
        'command_line' => @snapshot.kernel_command_line
      }
    end

    def livepatches
      @snapshot.kernel_livepatches.order(:livepatch_id).map do |livepatch|
        {
          'id' => livepatch.livepatch_id,
          'kernel_version' => livepatch.kernel_version,
          'patch_version' => livepatch.patch_version,
          'loaded' => livepatch.loaded,
          'enabled' => livepatch.enabled,
          'transition' => livepatch.transition,
          'applied_at' => iso8601(livepatch.applied_at),
          'verified_at' => iso8601(livepatch.verified_at),
          'patches' => livepatch.patches.order(:name).map do |patch|
            { 'name' => patch.name, 'version' => patch.version }
          end
        }
      end
    end

    def ebpf_programs
      @snapshot.ebpf_programs.order(:name).map do |program|
        {
          'name' => program.name,
          'description' => program.description,
          'sinceKernel' => program.since_kernel,
          'untilKernel' => program.until_kernel,
          'revision' => program.revision,
          'digest' => program.digest,
          'active' => program.active,
          'attached_at' => iso8601(program.attached_at),
          'verified_at' => iso8601(program.verified_at),
          'bpfPrograms' => program.program_objects.order(:name).pluck(:name),
          'links' => program.program_links.order(:name).to_h do |link|
            [link.name, link.attached]
          end
        }
      end
    end

    def software_versions
      @snapshot.software_versions.order(:generation, :component).map do |software|
        {
          'generation' => software.generation,
          'component' => software.component,
          'version' => software.version,
          'version_source' => software.version_source,
          'revision' => software.revision,
          'revision_source' => software.revision_source,
          'revision_dirty' => software.revision_dirty
        }
      end
    end

    def sysctls
      @snapshot.sysctls.order(:name).to_h do |sysctl|
        [
          sysctl.name,
          {
            'available' => sysctl.available,
            'configured' => sysctl.configured_value,
            'effective' => sysctl.effective_value
          }
        ]
      end
    end

    def iso8601(value) = value&.utc&.iso8601
  end
end
