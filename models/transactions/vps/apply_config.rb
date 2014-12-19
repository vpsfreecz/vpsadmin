module Transactions::Vps
  class ApplyConfig < ::Transaction
    t_name :vps_apply_config
    t_type 2008

    def params(vps)
      self.t_vps = vps.vps_id
      self.t_server = vps.vps_server

      ret = {
          configs: [],
          pool_fs: vps.dataset_in_pool.pool.filesystem,
          dataset_name: vps.dataset_in_pool.dataset.full_name
      }

      VpsHasConfig
        .includes(:vps_config)
        .where(vps_id: vps.veid,
               confirmed: [VpsHasConfig.confirmed(:confirm_create), VpsHasConfig.confirmed(:confirmed)])
        .order('`order` ASC').each do |c|
        ret[:configs] << c.vps_config.name
      end

      ret[:configs] << "vps-#{vps.veid}" unless vps.vps_config.empty?

      ret
    end
  end
end
