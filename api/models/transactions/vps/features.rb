module Transactions::Vps
  class Features < ::Transaction
    t_name :vps_features
    t_type 8001
    queue :vps

    def params(vps, features)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      res = {}

      features.each do |f|
        res[f.name] = {
          enabled: f.enabled,
          original: f.enabled_was,
        }
      end

      {features: res}
    end
  end
end
