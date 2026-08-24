require 'nodectld/container_state'

module NodeCtld
  # Represents an osctl container
  class Ct
    attr_reader :pool, :id, :user, :group, :dataset, :rootfs, :boot_dataset,
                :boot_rootfs, :config_state, :config_state_error,
                :runtime_state, :runtime_state_error, :init_pid

    # @param hash [Hash] hash given by osctl ct show/ls
    def initialize(hash)
      ContainerState.normalize(hash).each do |k, v|
        instance_variable_set("@#{k}", value(k, v))
      end
    end

    protected

    def value(k, v)
      case k
      when :config_state, :runtime_state
        v.to_sym

      else
        v
      end
    end
  end
end
