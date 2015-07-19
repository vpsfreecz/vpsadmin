module Transactions::IntegrityCheck
  class Storage < ::Transaction
    t_name :integrity_storage
    t_type 6005

    def params(check, node)
      @integrity_check = check
      self.t_server = node.id

      pools = []

      {
          pools: serialize_query(node.pools, nil, :add_pool),
          integrity_check_id: check.id
      }
    end

    protected
    def add_pool(pool, obj)

      {
          filesystem: pool.filesystem,
          properties: serialize_query(pool.dataset_properties, obj, :add_property),
          downloads: serialize_query(
              pool.snapshot_downloads,
              obj,
              :add_download
          ),
          mount_clones: serialize_query(
              ::SnapshotInPool.joins(
                :dataset_in_pool, mount: [:vps]
              ).where(
                  dataset_in_pools: {pool_id: pool.id}
              ).where.not(
                vps: {vps_server: pool.node_id}
              ),
              obj,
              :add_snapshot_clone
          ),
          datasets: serialize_query(
              pool.dataset_in_pools.includes(:dataset).where(
                  dataset: ::Dataset.roots.pluck(:id)
              ),
              obj,
              :add_dataset
          )
      }
    end

    def add_download(dl, obj)
      {
          secret_key: dl.secret_key,
          file_name: dl.file_name
      }
    end

    def add_snapshot_clone(snap, obj)
      {
          id: snap.snapshot.id,
          dataset: snap.snapshot.dataset.full_name,
          name: snap.snapshot.name
      }
    end

    def add_dataset(dip, obj)
      transaction_chain.lock(dip)

      {
          name: dip.dataset.full_name,
          properties: serialize_query(dip.dataset_properties, obj, :add_property),
          trees: serialize_query(dip.dataset_trees, obj, :add_tree),
          snapshots: dip.pool.role == 'backup' ? [] : serialize_query(
              dip.snapshot_in_pools.includes(:snapshot),
              obj,
              :add_snapshot
          ),
          datasets: serialize_query(
              ::DatasetInPool.where(
                  dataset_id: dip.dataset.child_ids,
                  pool: dip.pool
              ),
              obj,
              :add_dataset
          )
      }
    end

    def add_property(property, obj)
      {
          name: property.name,
          value: property.value,
          inherited: property.inherited
      }
    end

    def add_tree(tree, obj)
      {
          name: tree.full_name,
          branches: serialize_query(tree.branches, obj, :add_branch)
      }
    end

    def add_branch(branch, obj)
      {
          name: branch.full_name,
          snapshots: serialize_query(
              branch.snapshot_in_pool_in_branches,
              obj,
              :add_snapshot_in_branch
          )
      }
    end

    def add_snapshot_in_branch(snap, obj)
      origin = snap.snapshot_in_pool_in_branch

      {
          name: snap.snapshot_in_pool.snapshot.name,
          clones: serialize_query(
              ::Branch.joins(:snapshot_in_pool_in_branches).where(
                  snapshot_in_pool_in_branches: {
                      snapshot_in_pool_in_branch: snap
                  }
              ).group('branches.id'),
              obj,
              :add_snapshot_in_branch_clone
          ),
          origin: origin ? {
              dataset: origin.snapshot_in_pool.dataset_in_pool.dataset.full_name,
              tree: origin.branch.dataset_tree.full_name,
              branch: origin.branch.full_name,
              snapshot: origin.snapshot_in_pool.snapshot.name
          } : nil,
          reference_count: snap.snapshot_in_pool.reference_count
      }
    end

    def add_snapshot_in_branch_clone(branch, obj)
      {
          dataset: branch.dataset_tree.dataset_in_pool.dataset.full_name,
          tree: branch.dataset_tree.full_name,
          branch: branch.full_name
      }
    end

    def add_snapshot(snap, obj)
      {
          name: snap.snapshot.name,
          reference_count: snap.reference_count
          # clones of snapshots are handle on the pool level
      }
    end

    def serialize_query(q, parent, method)
      ret = []
            
      q.each do |obj|
        integrity_obj = register_object!(obj, parent)
        tmp = send(method, obj, integrity_obj)
        tmp[:integrity_object_id] = integrity_obj.id
        tmp[:ancestry] = integrity_obj.ancestry
        ret << tmp
      end

      ret
    end

    def register_object!(obj, parent = nil)
      ::IntegrityObject.create!(
          integrity_check: @integrity_check,
          class_name: obj.class.name,
          row_id: obj.id,
          parent: parent
      )
    end
  end
end
