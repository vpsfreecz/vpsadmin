module TransactionChains
  class VpsApplyConfig < ::TransactionChain
    label 'Change VPS configuration'

    # +new_configs+ is a list of config IDs.
    def link_chain(vps, new_configs)
      lock(vps)

      append(Transactions::Vps::ApplyConfig, args: vps) do
        # First remove old configs
        vps.vps_configs.all.each do |cfg|
          destroy cfg
        end

        VpsHasConfig.where(vps_id: vps.veid).update_all(confirmed: VpsHasConfig.confirmed(:confirm_create))

        # Create new configs
        i = 0

        new_configs.each do |c|
          create VpsHasConfig.create(vps_id: vps.veid, config_id: c, order: i, confirmed: VpsHasConfig.confirmed(:confirm_create))
          i += 1
        end
      end
    end
  end
end
