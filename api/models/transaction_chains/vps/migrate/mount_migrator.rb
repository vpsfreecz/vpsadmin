module TransactionChains
  # Handle mounts that exist inside the migrating VPS itself.
  #
  # Supported:
  # - remapping bind mounts of datasets from the migrated VPS subtree
  # - remapping subtree snapshot mounts to the mirrored snapshot on the target
  #
  # Historical cross-VPS / remote mount migration support has been removed.
  class Vps::Migrate::MountMigrator
    def initialize(chain, src_vps, dst_vps)
      @chain = chain
      @src_vps = src_vps
      @dst_vps = dst_vps
      @my_mounts = []
      @my_deleted = []

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

    def delete_mine_if
      @my_mounts.delete_if do |m|
        if yield(m)
          m.confirmed = ::Mount.confirmed(:confirm_destroy)
          m.save!
          @my_deleted << m

          true
        else
          false
        end
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

      return unless obj_changes.any? || @my_deleted.any?

      @chain.append_t(
        Transactions::Utils::NoOp,
        args: @dst_vps.node_id,
        urgent: true
      ) do |t|
        obj_changes.each do |obj, changes|
          t.edit_before(obj, changes)
        end

        @my_deleted.each do |m|
          t.destroy(m)
        end
      end
    end

    private

    def sort_mounts
      ::Mount.includes(
        :vps, :snapshot_in_pool, dataset_in_pool: [:dataset, { pool: [:node] }]
      ).where(
        vps_id: @src_vps.id
      ).order('dst DESC').each do |mnt|
        @my_mounts << mnt
      end
    end

    # Migrate a mount that is mounted in the migrated VPS.
    def migrate_mine_mount(mnt)
      dst_dip = @ds_map[mnt.dataset_in_pool]

      is_subdataset =
        mnt.dataset_in_pool.pool.node_id == @src_vps.node_id &&
        mnt.vps.dataset_in_pool.dataset.subtree_ids.include?(
          mnt.dataset_in_pool.dataset.id
        )

      is_local = @src_vps.node_id == mnt.dataset_in_pool.pool.node_id
      is_remote = !is_local

      become_local = @dst_vps.node_id == if is_subdataset
                                           dst_dip.pool.node_id
                                         else
                                           mnt.dataset_in_pool.pool.node_id
                                         end

      become_remote = !become_local

      is_snapshot = !mnt.snapshot_in_pool.nil?
      new_snapshot = if is_snapshot && is_subdataset
                       ::SnapshotInPool.where(
                         snapshot_id: mnt.snapshot_in_pool.snapshot_id,
                         dataset_in_pool: dst_dip
                       ).take!
                     end

      original = {
        dataset_in_pool_id: mnt.dataset_in_pool_id,
        snapshot_in_pool_id: mnt.snapshot_in_pool_id,
        snapshot_in_pool_clone_id: mnt.snapshot_in_pool_clone_id,
        mount_type: mnt.mount_type,
        mount_opts: mnt.mount_opts
      }

      changes = {}

      if (is_local && become_remote) || (is_remote && become_local)
        raise 'remote mounts not supported'
      end

      if is_subdataset
        mnt.vps = @dst_vps
        mnt.dataset_in_pool = dst_dip

        if is_snapshot
          # Remove the mount link from snapshot_in_pool, because it would
          # delete mount, when the snapshot gets deleted in
          # DatasetInPool::Destroy.
          changes[mnt.snapshot_in_pool] = {
            mount_id: mnt.snapshot_in_pool.mount_id
          }
          mnt.snapshot_in_pool.update!(mount: nil)

          changes[new_snapshot] = { mount_id: nil }
          new_snapshot.update!(mount: mnt)

          mnt.snapshot_in_pool = new_snapshot
        end
      end

      mnt.save!

      changes[mnt] = original
      changes
    end
  end
end
