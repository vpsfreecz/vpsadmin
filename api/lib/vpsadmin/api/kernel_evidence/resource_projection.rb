require 'delegate'

module VpsAdmin::API::KernelEvidence
  module ResourceProjection
    class Evidence < SimpleDelegator
      def initialize(evidence, evidence_revision: evidence.snapshot_revision)
        super(evidence)
        @evidence = evidence
        @evidence_revision = evidence_revision
      end

      attr_reader :evidence_revision

      def kernel_config_available
        digest = @evidence.kernel_config_digest
        digest.present? && ::NodeKernelConfiguration.exists?(digest:)
      end
    end

    class Event < SimpleDelegator
      EVIDENCE_FIELDS = %i[
        report_schema_version
        snapshot_revision
        kernel_source_revision
        kernel_config_digest
        kernel_command_line
        booted_system
        current_system
      ].freeze

      def initialize(event, evidence_revision: nil)
        super(event)
        @event = event
        @evidence = event.kernel_evidence
        @evidence_revision = evidence_revision || @evidence&.snapshot_revision
      end

      attr_reader :evidence_revision

      EVIDENCE_FIELDS.each do |field|
        define_method(field) { @evidence&.public_send(field) }
      end

      def kernel_config_available
        digest = @evidence&.kernel_config_digest
        digest.present? && ::NodeKernelConfiguration.exists?(digest:)
      end

      def source_revision = @evidence&.snapshot_revision

      def change_count = @event.software_changes.size

      def public_event_type
        case @event.event_type
        when 'reported_release_change'
          'reported_release_change'
        when 'livepatch_change'
          'livepatch'
        else
          @event.event_type
        end
      end
    end

    class Change < SimpleDelegator
      def initialize(change)
        super
        @change = change
      end

      def source_revision = @change.node_kernel_evidence&.snapshot_revision
    end
  end
end
