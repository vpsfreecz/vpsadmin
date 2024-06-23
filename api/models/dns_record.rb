class DnsRecord < ApplicationRecord
  belongs_to :dns_zone
  belongs_to :host_ip_address
end
