class AddVpsFeatureApparmorControlDir < ActiveRecord::Migration[7.0]
  class Vps < ActiveRecord::Base; end

  class VpsFeature < ActiveRecord::Base; end

  def up
    ::Vps.where('object_state < 3').each do |vps|
      ::VpsFeature.create!(
        vps_id: vps.id,
        name: 'apparmor_dirs',
        enabled: true
      )
    end
  end

  def down
    ::VpsFeature.where(name: 'apparmor_dirs').delete_all
  end
end
