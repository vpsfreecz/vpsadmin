module Transactions::Vps
  class Reinstall < ::Transaction
    t_name :vps_reinstall
    t_type 3003
    queue :vps

    def params(vps, template)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
          distribution: template.distribution,
          version: template.version,
          arch: template.arch,
          vendor: template.vendor,
          variant: template.variant,
      }
    end
  end
end
