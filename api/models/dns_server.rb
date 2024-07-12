class DnsServer < ApplicationRecord
  belongs_to :node
  has_many :dns_server_zones
  has_many :dns_zones, through: :dns_server_zones

  validates :name, presence: true
  validate :name, :check_name

  def check_name
    return unless name.end_with?('.')

    errors.add(:name, 'must not have a trailing dot')
  end

  def addr
    node.ip_addr
  end
end
