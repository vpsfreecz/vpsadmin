require_relative 'confirmable'

class DnsServerZone < ApplicationRecord
  belongs_to :dns_server
  belongs_to :dns_zone

  include Confirmable

  scope :existing, lambda {
    where(confirmed: [confirmed(:confirm_create), confirmed(:confirmed)])
  }

  # @return [String]
  def ip_addr
    dns_server.node.ip_addr
  end

  # @return [String]
  def server_name
    dns_server.name
  end
end
