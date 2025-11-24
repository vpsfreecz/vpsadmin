module TransactionChains
  class Vps::RescueLeave < ::TransactionChain
    label 'Rescue-'

    # @param vps [::Vps]
    def link_chain(vps)
      lock(vps.rescue_volume)
      lock(vps.storage_volume)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      use_chain(Vps::Stop, args: [vps])

      append_t(Transactions::Vps::RescueLeave, args: [vps]) do |t|
        t.edit(vps, rescue_volume_id: nil)
      end

      append_t(Transactions::Vps::Define, args: [vps], kwargs: { rescue_volume: nil })

      use_chain(Vps::Start, args: [vps])

      use_chain(StorageVolume::Destroy, args: [vps.rescue_volume])
    end
  end
end
