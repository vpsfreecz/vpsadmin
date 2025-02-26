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

      {
        pool_name: vps.dataset_in_pool.pool.name,
        pool_fs: vps.dataset_in_pool.pool.filesystem,
        dataset_name: vps.dataset_in_pool.dataset.full_name,
        userns_map: vps.user_namespace_map_id.to_s,
        map_mode: vps.map_mode,
        hostname: vps.manage_hostname ? vps.hostname : nil,
        distribution: vps.os_template.distribution,
        version: vps.os_template.version,
        arch: vps.os_template.arch,
        vendor: vps.os_template.vendor,
        variant: vps.os_template.variant,
        empty:
      }
    end
  end
end
