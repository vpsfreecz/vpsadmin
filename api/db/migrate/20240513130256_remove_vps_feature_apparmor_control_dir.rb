class RemoveVpsFeatureApparmorControlDir < ActiveRecord::Migration[7.1]
  class Vps < ActiveRecord::Base; end

  class VpsFeature < ActiveRecord::Base; end

  def up
    ::VpsFeature.where(name: 'apparmor_dirs').delete_all
  end

  def down
    ::Vps.where('object_state < 3').each do |vps|
      ::VpsFeature.create!(
        vps_id: vps.id,
        name: 'apparmor_dirs',
        enabled: true
      )
    end
  end
end
