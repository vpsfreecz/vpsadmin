module Transactions::Vps
  class Reinstall < ::Transaction
    t_name :vps_reinstall
    t_type 3003
    queue :vps

    def params(vps, template)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      if vps.container?
        {
          pool_name: vps.dataset_in_pool.pool.name,
          pool_fs: vps.dataset_in_pool.pool.filesystem,
          distribution: template.distribution,
          version: template.version,
          arch: template.arch,
          vendor: template.vendor,
          variant: template.variant
        }
      else
        {
          distribution: template.distribution,
          version: template.version,
          arch: template.arch,
          variant: template.variant
        }
      end
    end
  end
end
