module TransactionChains
  class Mail::VpsDatasetExpanded < ::TransactionChain
    label 'Dataset expanded'
    allow_empty

    def link_chain(dataset_expansion, new_refquota:, added_space: dataset_expansion.added_space)
      vps = dataset_expansion.vps
      dataset = dataset_expansion.dataset
      dataset_in_pool = dataset.primary_dataset_in_pool!

      concerns(:affect, [vps.class.name, vps.id])

      route_event!(
        'vps.dataset_expanded',
        user: vps.user,
        vps:,
        source: dataset_expansion,
        subject: "Dataset for VPS ##{vps.id} expanded",
        summary: "Dataset #{dataset.full_name} was expanded by #{added_space} MiB",
        parameters: {
          vps_id: vps.id,
          vps_hostname: vps.hostname,
          dataset_id: dataset.id,
          dataset_full_name: dataset.full_name,
          dataset_refquota: new_refquota,
          dataset_referenced: dataset_in_pool.referenced,
          expansion_id: dataset_expansion.id,
          original_refquota: dataset_expansion.original_refquota,
          new_refquota:,
          added_space:,
          expansion_count: dataset_expansion.expansion_count
        }
      )
    end
  end
end
