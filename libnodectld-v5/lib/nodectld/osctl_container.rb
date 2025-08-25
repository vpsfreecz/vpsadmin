module NodeCtld
  class OsCtlContainer
    # @return [String]
    attr_reader :id

    # @return [String]
    attr_reader :pool

    # @return [Integer]
    attr_reader :vps_id

    # @return [String]
    attr_reader :boot_dataset

    # @return [String]
    attr_reader :boot_rootfs

    # @return [String]
    attr_reader :state

    # @return [Integer, nil]
    attr_reader :init_pid

    # @param ct [Hash] output of ct show/list
    def initialize(ct)
      @ct = ct
      @init_pid = ct[:init_pid]&.to_i

      %i[boot_dataset boot_rootfs dataset id pool state].each do |v|
        instance_variable_set(:"@#{v}", ct[v])
      end

      @vps_id = @id.to_i
    end

    def [](key)
      @ct[key]
    end

    def in_ct_boot?
      @dataset != @boot_dataset && %r{/ct/\d+\.boot-\w+\z} =~ @boot_dataset
    end
  end
end
