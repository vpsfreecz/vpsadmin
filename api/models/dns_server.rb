class DnsServer < ApplicationRecord
  belongs_to :node
  has_many :dns_server_zones
  has_many :dns_zones, through: :dns_server_zones

  validates :name, presence: true
end
