module TransactionChains
  module NetworkInterface::Veth::Helpers
    def gen_mac
      # First three octets -- OUI
      octets = (1..3).map { rand(256) }

      # Mark as locally administered
      octets[0] &= 0xfe
      octets[0] |= 0x02

      # Last three octets -- NIC
      3.times { octets << rand(256) }

      octets.map { |v| '%02x' % [v] }.join(':')
    end
  end
end
