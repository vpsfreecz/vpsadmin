module TransactionChains
  class Vps::SetResources < ::TransactionChain
    label 'Set VPS resources'

    def link_chain(vps, resources)
      lock(vps)

      append(Transactions::Vps::Resources, args: [vps, resources]) do
        resources.each do |r|
          if r.confirmed == :confirmed
            edit(r, value: r.value)

          else
            create(r)
          end
        end
      end
    end
  end
end
