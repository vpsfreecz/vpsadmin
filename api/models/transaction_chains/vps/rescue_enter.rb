module TransactionChains
  class Vps::RescueEnter < ::TransactionChain
    label 'Rescue+'

    # @param vps [::Vps]
    # @param os_template [::OsTemplate]
    # @param rootfs_mountpoint [String, nil] mountpoint or nil
    def link_chain(vps, os_template, rootfs_mountpoint: nil)
      lock(vps.storage_volume)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      vps_stopped = false

      if vps.rescue_volume_id
        lock(vps.rescue_volume)

        use_chain(Vps::Stop, args: [vps])
        vps_stopped = true

        append_t(
          Transactions::StorageVolume::Format,
          args: [vps.rescue_volume],
          kwargs: { wipe: true, os_template: }
        )
      else
        vps.rescue_volume = use_chain(
          StorageVolume::Create,
          kwargs: {
            storage_pool: vps.storage_volume.storage_pool,
            user: vps.user,
            vps:,
            name: "rescue#{vps.id}",
            format: 'qcow2',
            size: 10 * 1024,
            label: "rescue#{vps.id}",
            filesystem: 'btrfs',
            os_template:
          }
        )

        lock(vps.rescue_volume)
      end

      use_chain(Vps::Stop, args: [vps]) unless vps_stopped

      append_t(Transactions::Vps::Define, args: [vps])

      append_t(Transactions::Vps::RescueEnter, args: [vps, os_template], kwargs: { rootfs_mountpoint: }) do |t|
        t.edit(vps, rescue_volume_id: vps.rescue_volume_id)
      end

      use_chain(Vps::Start, args: [vps])

      vps.user.user_public_keys.where(auto_add: true).each do |key|
        use_chain(Vps::DeployPublicKey, args: [vps, key], reversible: :keep_going)
      end
    end
  end
end
