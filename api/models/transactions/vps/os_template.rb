module Transactions::Vps
  class OsTemplate < ::Transaction
    t_name :vps_os_template
    t_type 2013
    queue :vps

    def params(vps, orig, os_template)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      if vps.node.vpsadminos?
        {
          new: {
            distribution: os_template.distribution,
            version: os_template.version,
          },
          original: {
            distribution: orig.distribution,
            version: orig.version,
          },
        }
      else
        {
          os_template: os_template.name,
          original: orig.name,
        }
      end
    end
  end
end
