class MacAddress < ApplicationRecord
  has_many :host_network_interfaces, class_name: 'NetworkInterface', foreign_key: :host_mac_address_id
  has_many :guest_network_interfaces, class_name: 'NetworkInterface', foreign_key: :guest_mac_address_id

  def self.generate!
    mac = new

    10.times do
      mac.addr = mac.generate_addr

      begin
        mac.save!
      rescue ActiveRecord::RecordNotUnique
        sleep(0.1)
        next
      else
        return mac
      end
    end

    raise 'Unable to generate a unique MAC address'
  end

  def generate_addr
    # First three octets -- OUI
    octets = (1..3).map { rand(256) }

    # Mark as locally administered
    octets[0] &= 0xfe
    octets[0] |= 0x02

    # Last three octets -- NIC
    3.times { octets << rand(256) }

    octets.map { |v| format('%02x', v) }.join(':')
  end
end
