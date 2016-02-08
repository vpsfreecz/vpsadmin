module TransactionChains
  class Vps::Restart < ::TransactionChain
    label 'Restart'

    def link_chain(vps)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      append_t(Transactions::Vps::Restart, args: vps) do |t|
        t.just_create(vps.log(:restart)) unless included?
      end
    end
  end
end
