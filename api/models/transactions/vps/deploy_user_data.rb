module Transactions::Vps
  class DeployUserData < ::Transaction
    t_name :vps_deploy_user_data
    t_type 2035
    queue :vps
    keep_going

    def params(vps, user_data, os_template: nil)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      os_template ||= vps.os_template

      {
        vps_uuid: vps.uuid.to_s,
        format: user_data.format,
        content: user_data.content.gsub("\r\n", "\n"),
        os_template: {
          distribution: os_template.distribution,
          version: os_template.version,
          arch: os_template.arch,
          vendor: os_template.vendor,
          variant: os_template.variant
        }
      }
    end
  end
end
