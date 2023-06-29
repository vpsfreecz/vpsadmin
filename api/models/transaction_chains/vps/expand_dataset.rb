module TransactionChains
  class Vps::ExpandDataset < ::TransactionChain
    label 'Expand'

    def link_chain(dataset_expansion)
      ds = dataset_expansion.dataset
      dip = ds.primary_dataset_in_pool!

      lock(dip)

      concerns(
        :affect,
        [dataset_expansion.vps.class.name, dataset_expansion.vps.id],
        [dataset_expansion.dataset.class.name, dataset_expansion.dataset.id],
      )

      dataset_expansion.original_refquota = dip.refquota
      dataset_expansion.save!

      orig_refquota = dip.refquota
      new_refquota = dip.refquota + dataset_expansion.added_space

      use_chain(Dataset::Set, args: [
        dip,
        {refquota: new_refquota},
        {
          reset_expansion: false,
          admin_override: true,
          admin_lock_type: 'no_lock',
        }
      ])

      if dataset_expansion.enable_notifications
        use_chain(Mail::VpsDatasetExpanded, args: [vps, dataset_expansion])
      end

      append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
        t.just_create(dataset_expansion)
        t.just_create(dataset_expansion.dataset_expansion_histories.create!(
          added_space: dataset_expansion.added_space,
          original_refquota: orig_refquota,
          new_refquota: new_refquota,
          admin: ::User.current,
        ))
        t.edit(ds, dataset_expansion_id: dataset_expansion.id)
      end

      dataset_expansion
    end
  end
end
