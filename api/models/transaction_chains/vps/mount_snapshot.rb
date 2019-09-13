module TransactionChains
  # Mount local or remote snapshots.
  class Vps::MountSnapshot < ::TransactionChain
    label 'Mount snapshot'

    # Clones snapshot to pool working dataset and mounts it locally
    # or remotely to +vps+ at +dst+.
    def link_chain(vps, snapshot, dst, opts)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

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
        confirmed: ::Mount.confirmed(:confirm_create),
        expiration_date: Time.now + 3 * 24 * 60 * 60
      )

      mnt.on_start_fail = opts[:on_start_fail] if opts[:on_start_fail]

      remote = false

      # Snapshot is present locally on hypervisor
      if hypervisor && hypervisor.dataset_in_pool.pool.node_id == vps.node_id
        clone_from = hypervisor
        mnt.mount_type = 'none'
        mnt.mount_opts = '-o bind'

      # Snapshot is present on hypervisor and NOT in backup
      elsif hypervisor && !backup
        clone_from = hypervisor
        remote = true

      # Snapshot is on primary and NOT in backup.
      elsif primary && !backup

        clone_from = primary
        remote = true

      # Snapshot is in backup only, mount remotely
      elsif backup
        clone_from = backup
        remote = true

      else
        fail 'snapshot is nowhere to be found!'
      end

      if clone_from.mount_id
        raise VpsAdmin::API::Exceptions::SnapshotAlreadyMounted, clone_from
      end

      if remote
        mnt.mount_opts = '-n -t nfs -overs=3'
        mnt.mount_type = 'nfs'
      end

      mnt.dataset_in_pool = clone_from.dataset_in_pool
      mnt.snapshot_in_pool = clone_from
      mnt.snapshot_in_pool_clone = use_chain(
        SnapshotInPool::UseClone,
        args: [clone_from, vps.node.vpsadminos? ? vps.userns_map : nil]
      )
      mnt.save!

      append_t(
        Transactions::Utils::NoOp,
        args: find_node_id
      ) do |t|
        t.create(mnt)
        t.edit(clone_from, mount_id: mnt.id)
        t.just_create(vps.log(:mount, {
          id: mnt.id,
          type: :snapshot,
          src: {
              id: mnt.snapshot_in_pool.snapshot_id,
              name: mnt.snapshot_in_pool.snapshot.name
          },
          dst: mnt.dst,
          mode: mnt.mode,
          on_start_fail: mnt.on_start_fail,
        }))
      end

      use_chain(Vps::Mounts, args: vps)
      use_chain(Vps::Mount, args: [vps, [mnt]])

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
