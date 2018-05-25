require 'ipaddress'

class CompressIpv6Addresses < ActiveRecord::Migration
  class Network < ActiveRecord::Base
    has_many :ip_addresses
  end

  class IpAddress < ActiveRecord::Base
    belongs_to :network
  end

  def up
    IpAddress.joins(:network).where(networks: {ip_version: 6}).each do |ip|
      ip.update!(ip_addr: IPAddress.parse("#{ip.ip_addr}/#{ip.prefix}").to_s)
    end
  end

  def down
    # Don't do anything, since manually added addresses were most likely
    # compressed already, we won't decompress them.
  end
end
