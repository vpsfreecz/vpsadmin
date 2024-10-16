class AddVpsFeatureImpermanence < ActiveRecord::Migration[7.1]
  class Vps < ActiveRecord::Base; end

  class VpsFeature < ActiveRecord::Base; end

  def up
    ::Vps.where('object_state < 3').each do |vps|
      ::VpsFeature.create!(
        vps_id: vps.id,
        name: 'impermanence',
        enabled: false
      )
    end
  end

  def down
    ::VpsFeature.where(name: 'impermanence').delete_all
  end
end
