class DnsServerZone < ApplicationRecord
  belongs_to :dns_server
  belongs_to :dns_zone

  # @return [String]
  def ip_addr
    dns_server.node.ip_address
  end

  # @return [String]
  def server_name
    dns_server.name
  end
end
