module TransactionChains
  class Vps::CreateVeth < ::TransactionChain
    label 'Veth+'

    def link_chain(vps)
      # Create veth interface
      append_t(Transactions::Vps::CreateVeth, args: vps) do |t|
        t.edit_before(vps, veth_mac: nil)
        gen_unique_mac(vps)
      end
    end

    protected
    def gen_unique_mac(vps)
      5.times do
        mac = gen_mac

        begin
          vps.update!(veth_mac: mac)

        rescue ActiveRecord::RecordNotUnique
          sleep(0.25)
          next
        end
      end

      if vps.veth_mac.nil?
        fail 'unable to generate unique mac address'
      end
    end

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
