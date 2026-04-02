# frozen_string_literal: true

module NodeCtldSpec
  module StorageCommandHelpers
    FakeDatasetState = Struct.new(:label) do
      attr_reader :applied_to

      def initialize(label)
        super
        @applied_to = []
      end

      def apply_to(dataset)
        @applied_to << dataset
        true
      end
    end

    def build_storage_driver
      instance_double(
        NodeCtld::Command,
        progress: nil,
        'progress=': nil,
        log_type: :spec
      )
    end

    def system_command_failed(cmd = 'zfs', rc: 1, output: 'not currently mounted')
      NodeCtld::SystemCommandFailed.new(cmd, rc, output)
    end
  end
end
