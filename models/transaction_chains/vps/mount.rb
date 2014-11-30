module TransactionChains
  # Create /etc/vz/conf/$veid.(u)mount scripts.
  # Contains mounts of storage datasets (NAS) and VPS subdatasets.
  class Vps::Mount < ::TransactionChain
    label 'Mount'

    def link_chain(vps, mounts)
      lock(vps)

      append(Transactions::Vps::Mount, args: [vps, mounts])
    end
  end
end
