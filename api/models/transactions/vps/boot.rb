module Transactions::Vps
  class Boot < ::Transaction
    t_name :vps_boot
    t_type 2029
    queue :vps

    # @param vps [::Vps]
    # @param template [::OsTemplate]
    # @param mount_root_dataset [String, nil] mountpoint or nil
    # @param start_timeout ['infinity', Integer]
    def params(vps, template, mount_root_dataset: nil, start_timeout: 'infinity')
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        distribution: template.distribution,
        version: template.version,
        arch: template.arch,
        vendor: template.vendor,
        variant: template.variant,
        mount_root_dataset: mount_root_dataset,
        start_timeout: start_timeout,
      }
    end
  end
end
