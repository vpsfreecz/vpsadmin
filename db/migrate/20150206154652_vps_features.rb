class VpsFeatures < ActiveRecord::Migration
  class Vps < ActiveRecord::Base
    self.table_name = 'vps'
    self.primary_key = 'vps_id'

    has_many :vps_features
  end

  class VpsFeature < ActiveRecord::Base
    belongs_to :vps

    FEATURES = %i(iptables tun fuse nfs ppp bridge)
  end

  def change
    create_table :vps_features do |t|
      t.references   :vps,          null: false
      t.string       :name,         null: false
      t.boolean      :enabled,      null: false
      t.datetime     :updated_at
    end

    add_index :vps_features, [:vps_id, :name], unique: true

    reversible do |dir|
      dir.up do
        Vps.all.each do |vps|
          VpsFeature::FEATURES.each do |f|
            vps.vps_features << VpsFeature.new(
                name: f,
                enabled: vps.vps_features_enabled
            )
          end
        end
      end

      dir.down do
        Vps.all.each do |vps|
          vps.vps_features_enabled = vps.vps_features.exists?(enabled: true)
          vps.save!
        end
      end
    end

    remove_column :vps, :vps_features_enabled, :boolean, null: false, default: false
  end
end
