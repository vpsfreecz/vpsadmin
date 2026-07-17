module VpsAdmin::API::SystemState
  class Normalizer
    ATTRIBUTES = %i[cpus total_memory total_swap cgroup_version].freeze

    def self.from_status(status)
      from_values(
        cpus: status.cpus,
        total_memory: status.total_memory,
        total_swap: status.total_swap,
        cgroup_version: status.cgroup_version
      )
    end

    def self.from_values(cpus:, total_memory:, total_swap:, cgroup_version:)
      cgroup_value = if cgroup_version.is_a?(Integer)
                       ::NodeSystemState.cgroup_versions.key(cgroup_version)
                     else
                       cgroup_version
                     end

      {
        cpus: positive_integer(cpus),
        total_memory: positive_integer(total_memory),
        total_swap: nonnegative_integer(total_swap),
        cgroup_version: ::NodeSystemState.cgroup_versions.has_key?(cgroup_value) ? cgroup_value : nil
      }
    end

    def self.same?(left, right)
      ATTRIBUTES.all? { |attribute| left[attribute] == right[attribute] }
    end

    class << self
      protected

      def positive_integer(value)
        value if value.is_a?(Integer) && value > 0
      end

      def nonnegative_integer(value)
        value if value.is_a?(Integer) && value >= 0
      end
    end
  end
end
