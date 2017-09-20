module TransactionChains
  class Vps::Start < ::TransactionChain
    label 'Start'

    def link_chain(vps)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      append_t(Transactions::Vps::Start, args: vps) do |t|
        t.just_create(vps.log(:start)) unless included?
      end
    end
  end
end
