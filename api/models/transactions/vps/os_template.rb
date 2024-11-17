module Transactions::Vps
  class OsTemplate < ::Transaction
    t_name :vps_os_template
    t_type 2013
    queue :vps

    def params(vps, orig, os_template)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        new: {
          distribution: os_template.distribution,
          version: os_template.version
        },
        original: {
          distribution: orig.distribution,
          version: orig.version
        }
      }
    end
  end
end
