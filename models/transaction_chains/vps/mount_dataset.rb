module TransactionChains
  # Mount local or remote datasets.
  class Vps::MountDataset < ::TransactionChain
    label 'Mount dataset'

    def link_chain(vps, dataset, dst, opts)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

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
          mode: opts[:mode],
          user_editable: false,
          dataset_in_pool: dip,
          confirmed: ::Mount.confirmed(:confirm_create)
      )

      mnt.on_start_fail = opts[:on_start_fail] if opts[:on_start_fail]

      if dip.pool.node_id == vps.vps_server
        mnt.mount_type = 'bind'
        mnt.mount_opts = '--bind'

      else
        mnt.mount_opts = '-n -t nfs -overs=3'
      end

      mnt.save!

      use_chain(Vps::Mounts, args: vps)
      use_chain(Vps::Mount, args: [vps, [mnt]])

      append(Transactions::Utils::NoOp, args: vps.vps_server) do
        create(mnt)
      end

      mnt
    end
  end
end
