class AddVpsFeaturePerHypervisorType < ActiveRecord::Migration
  class Node < ActiveRecord::Base
    has_many :vpses
    enum hypervisor_type: %i(openvz vpsadminos)
  end

  class Vps < ActiveRecord::Base
    belongs_to :node
    has_many :vps_features
  end

  class VpsFeature < ActiveRecord::Base
    belongs_to :vps
  end

  def up
    Vps.includes(:node).where('object_state < 3').each do |vps|
      case vps.node.hypervisor_type
      when 'openvz'
        remove_features(vps, ['lxc'])

      when 'vpsadminos'
        remove_features(vps, ['iptables', 'nfs', 'bridge'])

      else
        fail "unsupported hypervisor_type '#{vps.node.hypervisor_type}'"
      end
    end
  end

  def down
    Vps.includes(:node).where('object_state < 3').each do |vps|
      case vps.node.hypervisor_type
      when 'openvz'
        add_features(vps, ['lxc'])

      when 'vpsadminos'
        add_features(vps, ['iptables', 'nfs', 'bridge'])

      else
        fail "unsupported hypervisor_type '#{vps.node.hypervisor_type}'"
      end
    end
  end

  protected
  def remove_features(vps, features)
    vps.vps_features.where(name: features).delete_all
  end

  def add_features(vps, features)
    features.each do |f|
      ::VpsFeature.create!(
        vps_id: vps.id,
        name: f,
        enabled: false,
      )
    end
  end
end
