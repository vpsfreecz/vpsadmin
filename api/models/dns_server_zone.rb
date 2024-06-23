class DnsServerZone < ApplicationRecord
  belongs_to :dns_server
  belongs_to :dns_zone
end
