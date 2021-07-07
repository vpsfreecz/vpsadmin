module Transactions::Vps
  class ApplyConfig < ::Transaction
    t_name :vps_apply_config
    t_type 2008
    queue :vps

    def params(vps)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      ret = {
        configs: [],
        pool_fs: vps.dataset_in_pool.pool.filesystem,
        dataset_name: vps.dataset_in_pool.dataset.full_name,
      }

      VpsHasConfig
        .includes(:vps_config)
        .where(vps_id: vps.veid,
               confirmed: [VpsHasConfig.confirmed(:confirm_create), VpsHasConfig.confirmed(:confirmed)])
        .order(order: :asc).each do |c|
        ret[:configs] << c.vps_config.name
      end

      ret[:configs] << "vps-#{vps.veid}" unless vps.config.empty?

      ret
    end
  end
end
