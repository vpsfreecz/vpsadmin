module Transactions::Vps
  class RescueEnter < ::Transaction
    t_name :vps_rescue_enter
    t_type 2037
    queue :vps

    # @param vps [::Vps]
    # @param os_template [::OsTemplate]
    # @param rootfs_mountpoint [String, nil] mountpoint or nil
    def params(vps, os_template, rootfs_mountpoint: nil)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        vps_uuid: vps.uuid.to_s,
        rescue_label: vps.rescue_volume.label,
        rescue_rootfs_mountpoint: rootfs_mountpoint,
        rescue_system: {
          hostname: "rescue-#{vps.id}",
          os_family: os_template.os_family.name,
          distribution: os_template.distribution,
          version: os_template.version,
          arch: os_template.arch,
          variant: os_template.variant
        },
        standard_system: {
          hostname: vps.manage_hostname ? vps.hostname : nil,
          os_family: vps.os_family.name,
          distribution: vps.os_template.distribution,
          version: vps.os_template.version,
          arch: vps.os_template.arch,
          variant: vps.os_template.variant
        }
      }
    end
  end
end
