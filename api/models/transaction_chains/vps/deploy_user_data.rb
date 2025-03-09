module TransactionChains::Vps
  class DeployUserData < ::TransactionChain
    label 'User data'

    def link_chain(vps, user_data)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      append_t(Transactions::Vps::DeployUserData, args: [vps, user_data])
      nil
    end
  end
end
