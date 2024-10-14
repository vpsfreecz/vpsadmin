require 'vpsadmin/api/operations/base'
require 'vpsadmin/api/operations/dataset/utils'

module VpsAdmin::API
  class Operations::Dataset::UpdateProperties < Operations::Base
    include Operations::Dataset::Utils

    # @param dataset [::Dataset]
    # @param properties [Hash]
    # @param opts [Hash]
    # @return [::TransactionChain]
    def run(dataset, properties, opts)
      dip = dataset.primary_dataset_in_pool!

      check_refquota(
        dip,
        [],
        properties[:refquota]
      )

      chain, = TransactionChains::Dataset::Set.fire(
        dip,
        properties,
        opts
      )

      chain
    end
  end
end
