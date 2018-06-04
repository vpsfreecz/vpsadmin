class AddVpsFeatureDocker < ActiveRecord::Migration
  class Node < ActiveRecord::Base
    has_many :vpses
  end

  class Vps < ActiveRecord::Base
    belongs_to :node
  end

  class VpsFeature < ActiveRecord::Base ; end

  def up
    ::Vps.joins(:node).where('object_state < 3').where(
      nodes: {hypervisor_type: 1},
    ).each do |vps|
      ::VpsFeature.create!(
        vps_id: vps.id,
        name: 'docker',
        enabled: false,
      )
    end
  end

  def down
    ::VpsFeature.where(name: 'docker').delete_all
  end
end
