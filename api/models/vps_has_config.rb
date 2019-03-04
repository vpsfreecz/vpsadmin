require_relative 'confirmable'

class VpsHasConfig < ActiveRecord::Base
  belongs_to :vps
  belongs_to :vps_config

  has_paper_trail

  validates :vps_id, :vps_config_id, :order, presence: true,
            numericality: {only_integer: true}

  include Confirmable
end
