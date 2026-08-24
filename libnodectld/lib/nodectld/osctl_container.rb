require 'nodectld/container_state'

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
    attr_reader :config_state

    # @return [Hash, nil]
    attr_reader :config_state_error

    # @return [String]
    attr_reader :runtime_state

    # @return [Hash, nil]
    attr_reader :runtime_state_error

    # @return [Boolean]
    attr_reader :autostart

    # @return [Integer, nil]
    attr_reader :init_pid

    # @param ct [Hash] output of ct show/list
    def initialize(ct)
      @ct = ContainerState.normalize(ct)
      @init_pid = @ct[:init_pid]&.to_i

      %i[
        autostart
        boot_dataset
        boot_rootfs
        config_state
        config_state_error
        dataset
        id
        pool
        runtime_state
        runtime_state_error
      ].each do |v|
        instance_variable_set(:"@#{v}", @ct[v])
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
