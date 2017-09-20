module TransactionChains
  class Vps::Stop < ::TransactionChain
    label 'Stop'

    def link_chain(vps)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      append_t(Transactions::Vps::Stop, args: vps) do |t|
        t.just_create(vps.log(:stop)) unless included?
      end
    end
  end
end
