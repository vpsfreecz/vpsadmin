module NodeCtld
  # Represents an osctl container
  class Ct
    attr_reader :pool, :id, :user, :group, :dataset, :rootfs, :boot_dataset,
      :boot_rootfs, :state, :init_pid

    # @param hash [Hash] hash given by osctl ct show/ls
    def initialize(hash)
      hash.each do |k, v|
        instance_variable_set("@#{k}", value(k, v))
      end
    end

    protected
    def value(k, v)
      case k
      when :state
        v.to_sym

      else
        v
      end
    end
  end
end
