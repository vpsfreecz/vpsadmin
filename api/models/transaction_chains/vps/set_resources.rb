module TransactionChains
  class Vps::SetResources < ::TransactionChain
    label 'Resources'

    def link_chain(vps, resources, define_domain: true)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      append(Transactions::Vps::Resources, args: [vps, resources]) do
        resources.each do |r|
          if %i[confirmed confirm_destroy].include?(r.confirmed)
            edit(r, r.attr_changes)

          else
            create(r)
          end
        end
      end

      return if vps.container? || !define_domain

      append(Transactions::Vps::Define, args: [vps])
    end
  end
end
