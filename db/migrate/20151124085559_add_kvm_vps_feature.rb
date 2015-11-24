class AddKvmVpsFeature < ActiveRecord::Migration
  class Vps < ActiveRecord::Base
    self.table_name = 'vps'
    self.primary_key = 'vps_id'
 
    has_many :vps_features
  end

  class VpsFeature < ActiveRecord::Base
    belongs_to :vps
  end

  def up
    Vps.where('object_state < 3').each do |vps|
      vps.vps_features << VpsFeature.new(
          name: :kvm,
          enabled: false
      )
    end
  end

  def down
    VpsFeature.where(name: :kvm).delete_all
  end
end
