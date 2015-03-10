module TransactionChains
  # Create /etc/vz/conf/$veid.(u)mount scripts.
  # Contains mounts of storage datasets (NAS) and VPS subdatasets.
  class Vps::Mounts < ::TransactionChain
    label 'Mounts'

    def link_chain(vps, mounts = nil)
      lock(vps)
      set_concerns(:affect, [vps.class.name, vps.id])

      @vps = vps

      unless mounts
        mounts = []

        # Local/remote mounts
        vps.mounts.where.not(
            confirmed: ::Mount.confirmed(:confirm_destroy)
        ).order('dst ASC').each do |m|
          mounts << m
        end
      end

      append(Transactions::Vps::Mounts, args: [vps, mounts])
    end
  end
end
