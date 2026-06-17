module TransactionChains
  class Vps::ShrinkDataset < ::TransactionChain
    label 'Shrink'

    def link_chain(dataset_in_pool, dataset_expansion)
      lock(dataset_in_pool)
      concerns(
        :affect,
        [dataset_expansion.vps.class.name, dataset_expansion.vps.id],
        [dataset_expansion.dataset.class.name, dataset_expansion.dataset.id]
      )

      use_chain(Dataset::Set, args: [
                  dataset_in_pool,
                  { refquota: dataset_expansion.original_refquota },
                  {
                    reset_expansion: false,
                    admin_override: true,
                    admin_lock_type: 'no_lock'
                  }
                ])

      vps = dataset_expansion.vps
      dataset = dataset_expansion.dataset
      if vps.active? && dataset_expansion.enable_notifications
        route_event!(
          'vps.dataset_shrunk',
          user: vps.user,
          vps:,
          source: dataset_expansion,
          subject: "Dataset for VPS ##{vps.id} shrunk",
          summary: "Dataset #{dataset.full_name} was shrunk after temporary expansion",
          parameters: {
            vps_id: vps.id,
            vps_hostname: vps.hostname,
            dataset_id: dataset.id,
            dataset_full_name: dataset.full_name,
            dataset_refquota: dataset.refquota,
            dataset_referenced: dataset.referenced,
            expansion_id: dataset_expansion.id,
            original_refquota: dataset_expansion.original_refquota,
            added_space: dataset_expansion.added_space,
            expansion_count: dataset_expansion.expansion_count
          },
          email_vars: {
            base_url: ::SysConfig.get(:webui, :base_url),
            vps:,
            expansion: dataset_expansion,
            dataset:
          }
        )
      end

      append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
        t.edit(dataset_in_pool.dataset, dataset_expansion_id: nil)
        t.edit(dataset_expansion, state: ::DatasetExpansion.states[:resolved])
      end
    end
  end
end
