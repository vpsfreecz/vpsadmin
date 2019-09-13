module TransactionChains
  class SnapshotInPool::UseClone < ::TransactionChain
    # @param sip [SnapshotInPool]
    # @param userns_map [UserNamespaceMap]
    # @return [SnapshotInPoolClone]
    def link_chain(sip, userns_map)
      cl = ::SnapshotInPoolClone.where(
        snapshot_in_pool: sip,
        user_namespace_map: userns_map,
      ).take

      if cl.nil?
        create_clone(sip, userns_map)
      elsif cl.state != 'active'
        activate_clone(cl)
        cl
      else
        cl
      end
    end

    protected
    def create_clone(sip, userns_map)
      cl = ::SnapshotInPoolClone.create!(
        snapshot_in_pool: sip,
        user_namespace_map: userns_map,
        name: "#{sip.snapshot_id}-0.snapshot",
      )
      lock(cl)
      cl.update!(name: "#{sip.snapshot_id}-#{cl.id}.snapshot")

      append_t(
        Transactions::Storage::CloneSnapshot,
        args: [cl]
      ) do |t|
        t.increment(sip, :reference_count)
        t.create(cl)
      end

      cl
    end

    def activate_clone(cl)
      lock(cl)
      append_t(Transactions::Storage::ActivateSnapshotClone, args: [cl]) do |t|
        t.edit(cl, state: ::SnapshotInPoolClone.states[:active])
      end
    end
  end
end
