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
          umount_opts: '-f',
          mount_type: 'nfs',
          mode: 'ro',
          user_editable: false,
          confirmed: ::Mount.confirmed(:confirm_create)
      )

      # Snapshot is present locally on hypervisor
      if hypervisor && hypervisor.dataset_in_pool.pool.node_id = vps.vps_server
        clone_from = hypervisor
        mnt.mount_opts = '--bind'
        mnt.mount_type = 'bind'

      # Snapshot is on primary and NOT in backup.
      # TODO: transfer and mount from backup?
      elsif primary && !backup
        # Transfer to all backup pools
        # snapshot.dataset.dataset_in_pools.joins(:pool).where(pool: {role: ::Pool.roles[:backup]}).each do |backup_dip|
        #   use_chain(Dataset::Transfer, args: [primary.dataset_in_pool, backup_dip])
        # end

        clone_from = primary
        # FIXME: mount_opts

      # Snapshot is in backup only, mount remotely
      elsif backup
        clone_from = backup
        # FIXME: mount_opts

      else
        fail 'snapshot is nowhere to be found!'
      end

      mnt.snapshot_in_pool = clone_from
      mnt.save!

      append(Transactions::Storage::CloneSnapshot, args: clone_from) do
        create(mnt)
        increment(clone_from, :reference_count)
        edit(clone_from, mount_id: mnt.id)
      end

      use_chain(Vps::Mounts, args: vps)
      use_chain(Vps::Mount, args: [vps, [mnt]]) if vps.running

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
