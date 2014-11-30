module TransactionChains
  # Mount local or remote datasets without VPS restart.
  class Vps::Mount < ::TransactionChain
    label 'Mount'

    def link_chain(vps, mounts)
      lock(vps)

      append(Transactions::Vps::Mount, args: [vps, mounts])
    end
  end
end
