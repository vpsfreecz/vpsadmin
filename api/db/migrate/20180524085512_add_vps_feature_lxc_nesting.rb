class AddVpsFeatureLxcNesting < ActiveRecord::Migration
  class Vps < ActiveRecord::Base ; end
  class VpsFeature < ActiveRecord::Base ; end

  def up
    ::Vps.where('object_state < 3').each do |vps|
      ::VpsFeature.create!(
        vps_id: vps.id,
        name: 'lxc',
        enabled: false,
      )
    end
  end

  def down
    ::VpsFeature.where(name: 'lxc').delete_all
  end
end
