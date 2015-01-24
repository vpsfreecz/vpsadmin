module TransactionChains
  class Vps::SubdatasetCreate < ::TransactionChain
    label 'VPS subdataset+'

    def link_chain(vps, datasets)
      use_chain(Dataset::Create, args: [vps.dataset_in_pool, datasets])
    end
  end
end
