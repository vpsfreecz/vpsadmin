module TransactionChains
  class Vps::SoftDelete < ::TransactionChain
    label 'Soft delete'

    def link_chain(vps, target, state, log)
      lock(vps.dataset_in_pool)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      # Stop VPS - should be already stopped when suspended (blocked)
      use_chain(TransactionChains::Vps::Stop, args: vps)

      # FIXME: create new env config key to decide if IP addresses
      # should be kept or freed on soft delete.
      # Here it assumes that the only environment that does not use
      # ip ownership is playground, which is also the only environment
      # from thich IPs are freed.
      chain = self
      
      if !vps.node.environment.user_ip_ownership && target
        # Free IP address
        append(Transactions::Utils::NoOp, args: ::Node.first_available.id) do
          destroy(vps.free_resource!(:ipv4, chain: chain))
          destroy(vps.free_resource!(:ipv6, chain: chain)) # FIXME: ipv6 may not have been allocated
        end
      end
    end
  end
end
