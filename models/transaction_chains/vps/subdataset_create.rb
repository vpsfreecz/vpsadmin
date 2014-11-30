module TransactionChains
  class Vps::SubdatasetCreate < ::TransactionChain
    label 'VPS subdataset+'

    def link_chain(vps, datasets, mountpoints)
      opts = []

      mountpoints.each do |m|
        opts << {
            mountpoint: m,
            canmount: :noauto
        }
      end

      new_datasets = use_chain(Dataset::Create, vps.dataset_in_pool, datasets, opts)
      use_chain(Vps::Mounts, vps)
      use_chain(Vps::Mount, vps, new_datasets)
    end
  end
end
