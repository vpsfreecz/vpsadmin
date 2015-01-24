module TransactionChains
  # Mount local or remote datasets.
  class Vps::MountDataset < ::TransactionChain
    label 'Mount dataset'

    def link_chain(vps, dataset, dst, mode)
      lock(vps)

      dip = dataset.dataset_in_pools.joins(:pool).where(
          pools: {role: [::Pool.roles[:hypervisor], ::Pool.roles[:primary]]}
      ).take!

      lock(dip)

      mnt = ::Mount.new(
          vps: vps,
          dst: dst,
          mount_opts: '',
          umount_opts: '-f',
          mount_type: 'nfs',
          mode: mode,
          user_editable: false,
          dataset_in_pool: dip,
          confirmed: ::Mount.confirmed(:confirm_create)
      )

      if dip.pool.node_id == vps.vps_server
        mnt.mount_type = 'bind'
        mnt.mount_opts = '--bind'

      else
        mnt.mount_opts = '-overs=3'
      end

      mnt.save!

      use_chain(Vps::Mounts, args: vps)
      use_chain(Vps::Mount, args: [vps, [mnt]]) if vps.running

      mnt
    end
  end
end
