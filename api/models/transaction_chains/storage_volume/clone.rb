module TransactionChains
  class StorageVolume::Clone < ::TransactionChain
    label 'Clone'

    # @param src_volume [::StorageVolume]
    # @param dst_pool [::StoragePool]
    # @return [::StorageVolume]
    def link_chain(src_volume, dst_pool, name, user: nil)
      dst_volume = src_volume.dup
      dst_volume.storage_pool = dst_pool
      dst_volume.name = name
      dst_volume.user = user if user
      dst_volume.save!

      lock(dst_volume)

      dst_volume.allocate_resource!(
        :diskspace,
        dst_volume.size,
        user: dst_volume.user,
        chain: self
      )

      append_t(Transactions::StorageVolume::Clone, args: [src_volume, dst_volume]) do |t|
        t.create(dst_volume)
      end

      dst_volume
    end
  end
end
