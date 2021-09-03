class Vps < ::ActiveRecord::Base
  belongs_to :node
  has_many :vps_consoles
end
