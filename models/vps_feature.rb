class VpsFeature < ActiveRecord::Base
  belongs_to :vps

  FEATURES =  {
      iptables: 'iptables',
      tun: 'TUN/TAP',
      fuse: 'FUSE',
      nfs: 'NFS',
      ppp: 'PPP',
      bridge: 'Bridge',
      kvm: 'KVM',
  }

  validates :name, inclusion: {
      in: FEATURES.keys,
      message: '%{value} is not a valid feature'
  }

  def label
    FEATURES[name.to_sym]
  end
end
