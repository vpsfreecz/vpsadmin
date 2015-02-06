module Transactions::Vps
  class Features < ::Transaction
    t_name :vps_features
    t_type 8001

    def params(vps, features)
      self.t_vps = vps.vps_id
      self.t_server = vps.vps_server

      res = {}

      vps.vps_features.each do |f|
        n = features[f.name.to_sym]

        res[f.name] = {
            enabled: n.nil? ? f.enabled : n,
            original: f.enabled
        }
      end

      {features: res}
    end
  end
end
