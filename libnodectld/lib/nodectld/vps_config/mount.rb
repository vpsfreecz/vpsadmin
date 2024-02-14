module NodeCtld
  class VpsConfig::Mount
    ATTRIBUTES = %i[id on_start_fail type src_node_addr pool_fs dataset_name
                    snapshot_id snapshot dataset_tree branch dst
                    mount_opts umount_opts mode].freeze

    # @return [Integer]
    attr_reader :id

    # @return [String]
    attr_reader :on_start_fail

    # @return [String]
    attr_reader :type

    # @return [String]
    attr_reader :src_node_addr

    # @return [String]
    attr_reader :pool_fs

    # @return [String]
    attr_reader :dataset_name

    # @return [Integer]
    attr_reader :snapshot_id

    # @return [String]
    attr_reader :snapshot

    # @return [String]
    attr_reader :dataset_tree

    # @return [String]
    attr_reader :branch

    # @return [String]
    attr_reader :dst

    # @return [String]
    attr_reader :mount_opts

    # @return [String]
    attr_reader :umount_opts

    # @return [String]
    attr_reader :mode

    # @param data [Hash]
    def self.load(data)
      new(data.transform_keys(&:to_sym))
    end

    # @param opts [Hash] attributes
    def initialize(opts)
      ATTRIBUTES.each do |attr|
        instance_variable_set(:"@#{attr}", opts[attr]) if opts.has_key?(attr)
      end
    end

    def to_h
      ATTRIBUTES.to_h do |attr|
        [attr.to_s, instance_variable_get(:"@#{attr}")]
      end
    end

    def save
      to_h
    end
  end
end
