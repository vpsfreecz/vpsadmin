module TransactionChains
  class StorageVolume::Create < ::TransactionChain
    label 'Create'

    # @return [::StorageVolume]
    def link_chain(**attrs)
      os_template = attrs.delete(:os_template)

      vol = ::StorageVolume.create!(attrs)

      vol.allocate_resource!(
        :diskspace,
        vol.size,
        user: vol.user,
        chain: self
      )

      append_t(Transactions::StorageVolume::Create, args: [vol]) do |t|
        t.create(vol)
      end

      append_t(Transactions::StorageVolume::Format, args: [vol], kwargs: { os_template: })

      vol
    end
  end
end
