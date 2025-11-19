module Transactions::Vps
  class OsTemplate < ::Transaction
    t_name :vps_os_template
    t_type 2013
    queue :vps

    def params(vps, orig, os_template)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        vps_uuid: vps.uuid.to_s,
        new: {
          distribution: os_template.distribution,
          version: os_template.version,
          arch: os_template.arch,
          vendor: os_template.vendor,
          variant: os_template.variant
        },
        original: {
          distribution: orig.distribution,
          version: orig.version,
          arch: orig.arch,
          vendor: orig.vendor,
          variant: orig.variant
        }
      }
    end
  end
end
