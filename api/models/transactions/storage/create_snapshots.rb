module Transactions::Storage
  class CreateSnapshots < ::Transaction
    t_name :storage_create_snapshots
    t_type 5215
    storage_effect :snapshot_group_create
    queue :storage

    # Deliberately not configurable in production. Specs may stub this method
    # when exercising paired strict API/Node traffic on isolated databases.
    def self.test_only_strict_group_snapshot?
      false
    end

    def test_only_strict_group_snapshot?
      self.class.test_only_strict_group_snapshot?
    end

    def params(snapshot_in_pools)
      if test_only_strict_group_snapshot? && snapshot_in_pools.empty?
        raise 'strict group snapshot is empty'
      end

      self.node_id = snapshot_in_pools.first.dataset_in_pool.pool.node_id

      snapshots = []

      members = if test_only_strict_group_snapshot?
                  snapshot_in_pools.sort_by(&:id)
                else
                  snapshot_in_pools
                end
      members.each do |sip|
        snapshots << {
          pool_fs: sip.dataset_in_pool.pool.filesystem,
          dataset_name: sip.dataset_in_pool.dataset.full_name,
          snapshot_id: sip.snapshot_id
        }
      end

      return { snapshots: } unless test_only_strict_group_snapshot?

      names = members.map { |sip| sip.snapshot.name.delete_suffix(' (unconfirmed)') }
      { snapshots:, planned_snapshot_name: names.uniq.one? ? names.first : nil }
    end
  end
end
