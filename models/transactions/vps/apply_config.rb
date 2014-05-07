module Transactions::Vps
  class ApplyConfig < ::Transaction
    t_name :vps_apply_config
    t_type 2008

    def prepare(vps)
      self.t_vps = vps.vps_id
      self.t_server = vps.vps_server

      ret = {configs: []}

      vps.vps_configs.all.each do |c|
        ret[:configs] << c.name
      end

      ret[:configs] << "vps-#{vps.veid}" unless vps.vps_config.empty?

      ret
    end
  end
end
