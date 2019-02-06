module TransactionChains
  class NetworkInterface::Veth::Base < ::TransactionChain
    protected
    include NetworkInterface::Veth::Helpers

    # @param vps [::Vps]
    # @param type [String]
    # @param name [String]
    def create_netif(vps, type, name)
      create_unique do
        ::NetworkInterface.create!(
          vps: vps,
          kind: type,
          name: name,
          mac: gen_mac,
        )
      end
    end

    # @param src_netif [::NetworkInterface]
    # @param dst_vps [::Vps]
    def clone_netif(src_netif, dst_vps)
      create_unique do
        ::NetworkInterface.create!(
          vps: dst_vps,
          kind: src_netif.kind,
          name: src_netif.name,
          mac: gen_mac,
        )
      end
    end

    def create_unique
      5.times do
        begin
          return yield

        rescue ActiveRecord::RecordNotUnique
          sleep(0.25)
          next
        end
      end

      fail 'unable to create veth interface with a unique mac address'
    end
  end
end
