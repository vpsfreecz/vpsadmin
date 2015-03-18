module TransactionChains
  class Vps::ApplyConfig < ::TransactionChain
    label 'Change VPS configuration'

    # +new_configs+ is a list of config IDs.
    def link_chain(vps, new_configs)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      append(Transactions::Vps::ApplyConfig, args: vps) do
        # First remove old configs
        VpsHasConfig.where(
            vps_id: vps.veid,
            confirmed: VpsHasConfig.confirmed(:confirmed)).each do |cfg|
          destroy(cfg)
        end

        VpsHasConfig
          .where(vps_id: vps.veid,
                 confirmed: VpsHasConfig.confirmed(:confirmed))
          .update_all(confirmed: VpsHasConfig.confirmed(:confirm_destroy))

        # Create new configs
        i = 0

        new_configs.each do |c|
          create(VpsHasConfig.create(
              vps_id: vps.veid,
              config_id: c,
              order: i,
              confirmed: VpsHasConfig.confirmed(:confirm_create)
          ))
          i += 1
        end
      end
    end
  end
end
