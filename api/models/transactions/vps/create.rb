module Transactions::Vps
  class Create < ::Transaction
    t_name :vps_create
    t_type 3001
    queue :vps

    # @param vps [::Vps]
    # @param [Boolean] empty do not apply any template
    def params(vps, empty: false)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      if vps.node.openvz?
        {
          hostname: vps.hostname,
          template: vps.os_template.name,
          onboot: vps.node.location.vps_onboot,
        }

      else
        {
          pool_fs: vps.dataset_in_pool.pool.filesystem,
          dataset_name: vps.dataset_in_pool.dataset.full_name,
          userns_map: vps.userns_map.id.to_s,
          hostname: vps.manage_hostname ? vps.hostname : nil,
          distribution: vps.os_template.distribution,
          version: vps.os_template.version,
          arch: vps.os_template.arch,
          vendor: vps.os_template.vendor,
          variant: vps.os_template.variant,
          onboot: vps.node.location.vps_onboot,
          empty: empty,
        }
      end
    end
  end
end
