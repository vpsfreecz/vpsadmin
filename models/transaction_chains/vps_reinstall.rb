module TransactionChains
  class VpsReinstall < ::TransactionChain
    label 'Reinstall VPS'

    def link_chain(vps, template)
      lock(vps.dataset_in_pool)
      lock(vps)

      append(Transactions::Vps::Reinstall, args: [vps, template]) do
        edit(vps, vps_template: template.id)
      end

      append(Transactions::Vps::ApplyConfig, args: vps)
      # FIXME: regenerate mounts
    end
  end
end
