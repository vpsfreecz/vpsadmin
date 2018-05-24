class VpsFeature < ActiveRecord::Base
  belongs_to :vps

  Feature = Struct.new(:name, :label, :hypervisor_type) do
    def support?(node)
      hypervisor_type == :all || node.hypervisor_type.to_sym == hypervisor_type
    end
  end

  FEATURES = Hash[
    [
      Feature.new(:iptables, 'iptables', :openvz),
      Feature.new(:tun, 'TUN/TAP', :all),
      Feature.new(:fuse, 'FUSE', :all),
      Feature.new(:nfs, 'NFS', :openvz),
      Feature.new(:ppp, 'PPP', :all),
      Feature.new(:bridge, 'Bridge', :openvz),
      Feature.new(:kvm, 'KVM', :all),
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
end
