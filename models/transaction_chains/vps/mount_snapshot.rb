module TransactionChains
  # Mount local or remote snapshots.
  class Vps::MountSnapshot < ::TransactionChain
    label 'Mount snapshot'

    # Clones snapshot to pool working dataset and mounts it locally
    # or remotely to +vps+ at +dst+.
    def link_chain(vps, snapshot, dst)
      lock(vps)

      hypervisor, primary, backup = snap_in_pools(snapshot)
      clone_from = nil
      mnt = ::Mount.new(
          vps: vps,
          dst: dst,
          mount_opts: '',
          umount_opts: '-f',
          mount_type: 'nfs',
          mode: 'ro',
          user_editable: false,
          confirmed: ::Mount.confirmed(:confirm_create)
      )
      remote = false

      # Snapshot is present locally on hypervisor
      if hypervisor && hypervisor.dataset_in_pool.pool.node_id = vps.vps_server
        clone_from = hypervisor
        mnt.mount_type = 'zfs'
        mnt.mount_opts = '-t zfs'

      # Snapshot is on primary and NOT in backup.
      # TODO: transfer and mount from backup?
      elsif primary && !backup
        # Transfer to all backup pools
        # snapshot.dataset.dataset_in_pools.joins(:pool).where(pool: {role: ::Pool.roles[:backup]}).each do |backup_dip|
        #   use_chain(Dataset::Transfer, args: [primary.dataset_in_pool, backup_dip])
        # end

        clone_from = primary
        remote = true
        # FIXME: mount_opts

      # Snapshot is in backup only, mount remotely
      elsif backup
        clone_from = backup
        remote = true
        # FIXME: mount_opts

      else
        fail 'snapshot is nowhere to be found!'
      end

      if clone_from.mount_id
        raise VpsAdmin::API::Exceptions::SnapshotAlreadyMounted, clone_from
      end

      mnt.snapshot_in_pool = clone_from
      mnt.save!

      if remote
        append(Transactions::Storage::CloneSnapshot, args: clone_from) do
          create(mnt)
          increment(clone_from, :reference_count)
          edit(clone_from, mount_id: mnt.id)
        end
      end

      use_chain(Vps::Mounts, args: vps)
      use_chain(Vps::Mount, args: [vps, [mnt]]) if vps.running

      unless remote
        append(Transactions::Utils::NoOp, args: vps.vps_server) do
          create(mnt)
          increment(clone_from, :reference_count)
          edit(clone_from, mount_id: mnt.id)
        end
      end

      mnt
    end

    protected
    def snap_in_pools(snapshot)
      hv = pr = bc = nil

      snapshot.snapshot_in_pools
          .includes(dataset_in_pool: [:pool])
          .joins(dataset_in_pool: [:pool])
          .all.group('pools.role').each do |sip|
        case sip.dataset_in_pool.pool.role.to_sym
          when :hypervisor
            hv = sip

          when :primary
            pr = sip

          when :backup
            bc = sip
        end
      end

      [hv, pr, bc]
    end
  end
end
