module Transactions::Vps
  class VzToOs < ::Transaction
    t_name :vps_vztoos
    t_type 2024
    queue :vps
    keep_going

    # @param vps [::Vps]
    # @param mounts_to_exports [TransactionChains::Vps::Migrate::MountMigrator::MountToExport]
    def params(vps, mounts_to_exports)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        distribution: vps.os_template.distribution,
        version: vps.os_template.version,
        mounts_to_exports: mounts_to_exports.map do |m_ex|
          {
            dataset_id: m_ex.mount.dataset_in_pool.dataset_id,
            dataset_name: m_ex.mount.dataset_in_pool.dataset.full_name,
            server_address: m_ex.export.host_ip_address.ip_addr,
            server_path: m_ex.export.path,
            mountpoint: m_ex.mount.dst,
            mode: m_ex.mount.mode,
            nofail: %w(skip mount_later).include?(m_ex.mount.on_start_fail),
            enabled: m_ex.mount.enabled?,
          }
        end,
      }
    end
  end
end
