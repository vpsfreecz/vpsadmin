module Transactions::Storage
  class CreateSnapshot < ::Transaction
    t_name :storage_create_snapshot
    t_type 5204
    queue :storage
    storage_effect :snapshot_create

    def params(snapshot_in_pool)
      self.node_id = snapshot_in_pool.dataset_in_pool.pool.node_id
      @storage_mutation_subject = snapshot_in_pool

      {
        pool_fs: snapshot_in_pool.dataset_in_pool.pool.filesystem,
        dataset_name: snapshot_in_pool.dataset_in_pool.dataset.full_name,
        snapshot_id: snapshot_in_pool.snapshot_id,
        planned_snapshot_name: snapshot_in_pool.snapshot.name.delete_suffix(' (unconfirmed)')
      }
    end

    def storage_mutation_subject
      return if @storage_mutation_subject.dataset_in_pool.pool.backup?

      @storage_mutation_subject
    end
  end
end
