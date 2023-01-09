class VpsFeature < ActiveRecord::Base
  belongs_to :vps

  Feature = Struct.new(:name, :label, :hypervisor_type, :opts) do
    def initialize(*_, **_)
      super

      self.opts ||= {}
    end

    def support?(node)
      hypervisor_type == :all || node.hypervisor_type.to_sym == hypervisor_type
    end

    # @param name [Symbol]
    def conflict?(name)
      opts[:blocks] && opts[:blocks].include?(name)
    end

    def default?
      opts[:default] ? true : false
    end
  end

  FEATURES = Hash[
    [
      Feature.new(:tun, 'TUN/TAP', :all, default: true),
      Feature.new(:fuse, 'FUSE', :all, default: true),
      Feature.new(:ppp, 'PPP', :all),
      Feature.new(:kvm, 'KVM', :all, default: true),
      Feature.new(:lxc, 'LXC nesting', :vpsadminos),
    ].map { |f| [f.name, f] }
  ]

  validates :name, inclusion: {
    in: FEATURES.keys.map(&:to_s),
    message: '%{value} is not a valid feature'
  }

  def label
    FEATURES[name.to_sym].label
  end

  # @param other [VpsFeature]
  def conflict?(other)
    enabled && other.enabled && FEATURES[name.to_sym].conflict?(other.name.to_sym)
  end

  def set_to_default
    self.enabled = FEATURES[name.to_sym].default?
  end
end
