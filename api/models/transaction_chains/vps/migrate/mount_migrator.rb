module TransactionChains
  # Handle my mounts of datasets and snapshots of other VPSes
  #
  #  - local -> local
  #    - no change needed
  #  - local -> remote
  #    - change mount, create clone for snapshot if needed
  #  - remote -> remote
  #    - regenerate mounts to handle different IPs, move snapshot clone
  #      to new destination
  #  - remote -> local
  #    - change mount, remove clone of snapshot if needed
  #
  # Handling of mounts of my datasets and snapshots in other VPSes is the same.
  class Vps::Migrate::MountMigrator
    def initialize(chain, src_vps, dst_vps)
      @chain = chain
      @src_vps = src_vps
      @dst_vps = dst_vps
      @my_mounts = []
      @others_mounts = {}

      sort_mounts
    end

    def datasets=(datasets)
      # Map of source datasets to destination datasets
      @ds_map = {}

      datasets.each do |pair|
        # @ds_map[ src ] = dst
        @ds_map[pair[0]] = pair[1]
      end
    end

    def umount_others
      @others_mounts.each do |v, vps_mounts|
        @chain.append(
          Transactions::Vps::Umount,
          args: [v, vps_mounts.select { |m| m.enabled? }]
        )
      end
    end

    def remount_mine
      obj_changes = {}

      @my_mounts.each do |m|
        obj_changes.update(
          migrate_mine_mount(m)
        )
      end

      @chain.use_chain(Vps::Mounts, args: @dst_vps, urgent: true)

      unless obj_changes.empty?
        @chain.append(Transactions::Utils::NoOp, args: @dst_vps.node_id,
                      urgent: true) do
          obj_changes.each do |obj, changes|
            edit_before(obj, changes)
          end
        end
      end
    end

    def remount_others
      @others_mounts.each do |vps, mounts|
        obj_changes = {}

        mounts.each do |m|
          obj_changes.update(
            migrate_others_mount(m)
          )
        end

        @chain.use_chain(Vps::Mounts, args: vps, urgent: true)

        @chain.append(
          Transactions::Vps::Mount,
          args: [vps, mounts.select { |m| m.enabled? }.reverse],
          urgent: true
        ) do
          obj_changes.each do |obj, changes|
            edit_before(obj, changes)
          end
        end
      end
    end

    private
    def sort_mounts
      # Fetch ids of all descendant datasets in pool
      dataset_in_pools = @src_vps.dataset_in_pool.dataset.subtree.joins(
        :dataset_in_pools
      ).where(
        dataset_in_pools: {pool_id: @src_vps.dataset_in_pool.pool_id}
      ).pluck('dataset_in_pools.id')

      # Fetch all snapshot in pools of above datasets
      snapshot_in_pools = []

      ::SnapshotInPool.where(dataset_in_pool_id: dataset_in_pools).each do |sip|
        snapshot_in_pools << sip.id

        if sip.reference_count > 1
          # This shouldn't be possible, as every snapshot can be mounted
          # just once.
          fail "snapshot (s=#{sip.snapshot_id},sip=#{sip.id}) has too high a reference count"
        end
      end

      ::Mount.includes(
        :vps, :snapshot_in_pool, dataset_in_pool: [:dataset, pool: [:node]]
      ).where(
        'vps_id = ? OR (dataset_in_pool_id IN (?) OR snapshot_in_pool_id IN (?))',
        @src_vps.id, dataset_in_pools, snapshot_in_pools
      ).order('dst DESC').each do |mnt|
        if mnt.vps_id == @src_vps.id
          @my_mounts << mnt

        else
          @others_mounts[mnt.vps] ||= []
          @others_mounts[mnt.vps] << mnt
        end
      end
    end

    # Migrate a mount that is mounted in the migrated VPS (therefore mine)
    # and the mounted dataset or snapshot can be of the migrated VPS or from
    # elsewhere.
    def migrate_mine_mount(mnt)
      dst_dip = @ds_map[mnt.dataset_in_pool]

      is_subdataset = \
        mnt.dataset_in_pool.pool.node_id == @src_vps.node_id && \
        mnt.vps.dataset_in_pool.dataset.subtree_ids.include?(
          mnt.dataset_in_pool.dataset.id
        )

      is_local = @src_vps.node_id == mnt.dataset_in_pool.pool.node_id
      is_remote = !is_local

      if is_subdataset
        become_local = @dst_vps.node_id == dst_dip.pool.node_id
      else
        become_local = @dst_vps.node_id == mnt.dataset_in_pool.pool.node_id
      end

      become_remote = !become_local

      is_snapshot = !mnt.snapshot_in_pool.nil?
      new_snapshot = if is_snapshot && is_subdataset
                       ::SnapshotInPool.where(
                         snapshot_id: mnt.snapshot_in_pool.snapshot_id,
                         dataset_in_pool: dst_dip
                       ).take!
                     else
                       nil
                     end

      original = {
        dataset_in_pool_id: mnt.dataset_in_pool_id,
        snapshot_in_pool_id: mnt.snapshot_in_pool_id,
        snapshot_in_pool_clone_id: mnt.snapshot_in_pool_clone_id,
        mount_type: mnt.mount_type,
        mount_opts: mnt.mount_opts
      }

      changes = {}

      # Local -> remote:
      #   - change mount type
      #   - clone snapshot if needed
      if is_local && become_remote
        mnt.mount_type = 'nfs'
        mnt.mount_opts = '-n -t nfs -overs=3'

        if is_snapshot
          mnt.snapshot_in_pool_clone = @chain.use_chain(
            SnapshotClone::UseClone,
            args: [mnt.snapshot_in_pool, mnt.vps.userns_map],
            urgent: true,
          )
        end

      # Remote -> local:
      #   - change mount type
      #   - remote snapshot clone if needed
      elsif is_remote && become_local
        mnt.mount_type = 'bind'
        mnt.mount_opts = '--bind'

        if is_snapshot
          @chain.use_chain(
            SnapshotClone::FreeClone,
            args: [mnt.snapshot_in_pool_clone],
            urgent: true,
          )

          mnt.snapshot_in_pool_clone = nil
        end

      # Remote -> remote:
      elsif is_remote && become_remote

      # Local -> local:
      #   - nothing to do
      elsif is_local && become_local

      end

      if is_subdataset
        mnt.dataset_in_pool = dst_dip

        if is_snapshot
          # Remove the mount link from snapshot_in_pool, because it would
          # delete mount, when the snapshot gets deleted in
          # DatasetInPool::Destroy.
          changes[mnt.snapshot_in_pool] = {
            mount_id: mnt.snapshot_in_pool.mount_id
          }
          mnt.snapshot_in_pool.update!(mount: nil)

          changes[new_snapshot] = {mount_id: nil}
          new_snapshot.update!(mount: mnt)

          mnt.snapshot_in_pool = new_snapshot
        end
      end

      mnt.save!

      changes[mnt] = original
      changes
    end

    # Migrate a mount that is mounted in another VPS (not the one being
    # migrated). The mounted dataset or snapshot belongs to the migrated VPS.
    def migrate_others_mount(mnt)
      dst_dip = @ds_map[mnt.dataset_in_pool]

      is_local = @src_vps.node_id == mnt.vps.node_id
      is_remote = !is_local

      become_local = @dst_vps.node_id == mnt.vps.node_id
      become_remote = !become_local

      is_snapshot = !mnt.snapshot_in_pool.nil?
      new_snapshot = if is_snapshot
                       ::SnapshotInPool.where(
                         snapshot_id: mnt.snapshot_in_pool.snapshot_id,
                         dataset_in_pool: dst_dip
                       ).take!
                     else
                       nil
                     end

      original = {
        dataset_in_pool_id: mnt.dataset_in_pool_id,
        snapshot_in_pool_id: mnt.snapshot_in_pool_id,
        snapshot_in_pool_clone_id: mnt.snapshot_in_pool_clone_id,
        mount_type: mnt.mount_type,
        mount_opts: mnt.mount_opts
      }

      changes = {}

      # Local -> remote:
      #   - change mount type
      #   - clone snapshot if needed
      if is_local && become_remote
        mnt.mount_type = 'nfs'
        mnt.mount_opts = '-n -t nfs -overs=3'

        if is_snapshot
          mnt.snapshot_in_pool_clone = @chain.use_chain(
            SnapshotInPool::UseClone,
            args: [new_snapshot, mnt.vps.userns_map],
            urgent: true,
          )
        end

      # Remote -> local:
      #   - change mount type
      #   - remote snapshot clone if needed
      elsif is_remote && become_local
        mnt.mount_type = 'bind'
        mnt.mount_opts = '--bind'

        if is_snapshot
          @chain.use_chain(
            SnapshotInPool::FreeClone,
            args: [mnt.snapshot_in_pool_clone],
            urgent: true,
          )

          mnt.snapshot_in_pool_clone = nil
        end

      # Remote -> remote:
      #   - update node IP address, remove snapshot on src and create on dst
      #     node
      elsif is_remote && become_remote
        if is_snapshot
          @chain.use_chain(
            SnapshotInPool::FreeClone,
            args: [mnt.snapshot_in_pool_clone],
            urgent: true,
          )
          mnt.snapshot_in_pool_clone = @chain.use_chain(
            SnapshotInPool::UseClone,
            args: [new_snapshot, mnt.vps.userns_map],
            urgent: true,
          )
        end

      # Local -> local:
      #   - nothing to do
      elsif is_local && become_local

      end

      mnt.dataset_in_pool = dst_dip

      if is_snapshot
        # Remove the mount link from snapshot_in_pool, because it would
        # delete mount, when the snapshot gets deleted in
        # DatasetInPool::Destroy.
        changes[mnt.snapshot_in_pool] = {
          mount_id: mnt.snapshot_in_pool.mount_id
        }
        mnt.snapshot_in_pool.update!(mount: nil)

        changes[new_snapshot] = {mount_id: nil}
        new_snapshot.update!(mount: mnt)

        mnt.snapshot_in_pool = new_snapshot
      end

      mnt.save!

      changes[mnt] = original
      changes
    end
  end
end
