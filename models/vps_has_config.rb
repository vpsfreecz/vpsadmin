class VpsHasConfig < ActiveRecord::Base
  self.table_name = 'vps_has_config'
  self.primary_key = [:vps_id, :config_id]

  belongs_to :vps
  belongs_to :vps_config, foreign_key: :config_id

  has_paper_trail

  validates :vps_id, :config_id, :order, presence: true,
            numericality: {only_integer: true}

  include Confirmable
end
