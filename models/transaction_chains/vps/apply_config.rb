module TransactionChains
  class Vps::ApplyConfig < ::TransactionChain
    label 'Apply config'

    # +new_configs+ is a list of config IDs.
    def link_chain(vps, new_configs, resources: false)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      append_t(Transactions::Vps::ApplyConfig, args: vps) do |t|
        # First remove old configs
        VpsHasConfig.where(
            vps_id: vps.veid,
            confirmed: VpsHasConfig.confirmed(:confirmed)).each do |cfg|
          t.destroy(cfg)
        end

        VpsHasConfig
          .where(vps_id: vps.veid,
                 confirmed: VpsHasConfig.confirmed(:confirmed))
          .update_all(confirmed: VpsHasConfig.confirmed(:confirm_destroy))

        # Create new configs
        i = 0
        data = []

        new_configs.each do |c|
          t.create(VpsHasConfig.create(
              vps_id: vps.veid,
              config_id: c,
              order: i,
              confirmed: VpsHasConfig.confirmed(:confirm_create)
          ))

          data << ::VpsConfig.find(c).name
          i += 1
        end

        t.just_create(vps.log(:configs, data)) unless included?
      end

      append(Transactions::Vps::Resources, args: [
          vps,
          vps.get_cluster_resources(%i(cpu memory swap)),
      ]) if resources
    end
  end
end
