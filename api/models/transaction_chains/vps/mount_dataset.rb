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

      # Forbid mounts of vpsAdminOS datasets, unless dip is a subdataset of vps
      if dip.pool.node.vpsadminos? && dip.pool.role == 'hypervisor'
        if !vps.dataset_in_pool.dataset.root_of?(dip.dataset)
          raise VpsAdmin::API::Exceptions::OperationNotSupported,
                "Only VPS subdatasets can be mouted using vpsAdmin"
        elsif dip.pool.node_id != vps.node_id
          raise VpsAdmin::API::Exceptions::OperationNotSupported,
                "Datasets on vpsAdminOS cannot be mounted remotely"
        end
      end

      # Forbid remote mounts to vpsAdminOS VPS
      if vps.node.vpsadminos? && dip.pool.node_id != vps.node_id
        raise VpsAdmin::API::Exceptions::OperationNotSupported,
              "Remote mounts on vpsAdminOS are not supported, export your "+
              "dataset and mount it from your VPS manually using NFS"
      end

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

      if dip.pool.node_id == vps.node_id
        mnt.mount_type = 'bind'
        mnt.mount_opts = '--bind'

      else
        mnt.mount_opts = '-n -t nfs -overs=3'
      end

      mnt.save!

      use_chain(Vps::Mounts, args: vps)
      use_chain(Vps::Mount, args: [vps, [mnt]])

      append(Transactions::Utils::NoOp, args: vps.node_id) do
        create(mnt)
        just_create(vps.log(:mount, {
          id: mnt.id,
          type: :dataset,
          src: {
            id: mnt.dataset_in_pool.dataset_id,
            name: mnt.dataset_in_pool.dataset.full_name
          },
          dst: mnt.dst,
          mode: mnt.mode,
          on_start_fail: mnt.on_start_fail,
        }))
      end

      mnt
    end
  end
end
