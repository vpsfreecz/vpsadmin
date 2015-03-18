module TransactionChains
  # Mount local or remote datasets without VPS restart.
  class Vps::Mount < ::TransactionChain
    label 'Mount'

    def link_chain(vps, mounts)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      append(Transactions::Vps::Mount, args: [vps, mounts])
    end
  end
end
