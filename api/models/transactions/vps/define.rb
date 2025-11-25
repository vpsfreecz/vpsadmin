module Transactions::Vps
  class Define < ::Transaction
    t_name :vps_define
    t_type 2040
    queue :vps

    # @param vps [::Vps]
    # @param rollback_undefine [Boolean] undefine on rollback
    # @param kwargs [Hash] overrides
    def params(vps, rollback_undefine: false, **kwargs)
      self.vps_id = vps.id
      self.node_id = kwargs.fetch(:node, vps.node).id

      rescue_volume = kwargs.fetch(:rescue_volume, vps.rescue_volume)

      {
        rollback_undefine:,
        vps_uuid: vps.uuid.to_s,
        vm_type: vps.vm_type,
        os: vps.os_family.os.name,
        os_family: vps.os_family.name,
        cpu: vps.cpu,
        cpu_limit: vps.cpu_limit,
        memory: vps.memory,
        rootfs_volume: {
          id: vps.storage_volume_id,
          pool_path: vps.storage_volume.storage_pool.path,
          name: vps.storage_volume.name,
          format: vps.storage_volume.format,
          label: vps.storage_volume.label
        },
        rescue_volume: rescue_volume && {
          id: rescue_volume.id,
          pool_path: rescue_volume.storage_pool.path,
          name: rescue_volume.name,
          format: rescue_volume.format,
          label: rescue_volume.label
        },
        network_interfaces: kwargs.fetch(:network_interfaces, vps.network_interfaces).map do |netif|
          {
            host_name: netif.host_name,
            guest_name: netif.guest_name,
            user_id: netif.vps.user_id,
            netif_id: netif.id,
            host_mac: netif.host_mac_address.addr,
            guest_mac: netif.guest_mac_address.addr,
            max_tx: netif.max_tx,
            max_rx: netif.max_rx,
            enable: netif.enable
          }
        end,
        console_port: vps.console_port.port,
        cgroup_version: vps.cgroup_version_number
      }
    end
  end
end
