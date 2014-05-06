class VpsConfig < ActiveRecord::Base
  self.table_name = 'config'

  has_many :vps_has_config, foreign_key: :config_id
  has_many :vpses, through: :vps_has_config

  validates :name, :label, :config, presence: true
end
