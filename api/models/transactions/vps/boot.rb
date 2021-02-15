module Transactions::Vps
  class Boot < ::Transaction
    t_name :vps_boot
    t_type 2029
    queue :vps

    # @param vps [::Vps]
    # @param template [::OsTemplate]
    # @param opts [Hash]
    # @option opts [String, nil] :mount_root_dataset mountpoint or nil
    def params(vps, template, opts = {})
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        distribution: template.distribution,
        version: template.version,
        arch: template.arch,
        vendor: template.vendor,
        variant: template.variant,
        mount_root_dataset: opts[:mount_root_dataset],
      }
    end
  end
end
