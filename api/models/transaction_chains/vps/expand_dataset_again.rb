module TransactionChains
  class Vps::ExpandDatasetAgain < ::TransactionChain
    label 'Expand+'

    def link_chain(dataset_expansion_history)
      exp = dataset_expansion_history.dataset_expansion
      ds = exp.dataset
      dip = ds.primary_dataset_in_pool!

      lock(dip)

      concerns(
        :affect,
        [exp.vps.class.name, exp.vps.id],
        [exp.dataset.class.name, exp.dataset.id]
      )

      new_refquota = dip.refquota + dataset_expansion_history.added_space

      dataset_expansion_history.original_refquota = dip.refquota
      dataset_expansion_history.new_refquota = new_refquota
      dataset_expansion_history.save!

      use_chain(Dataset::Set, args: [
                  dip,
                  { refquota: new_refquota },
                  {
                    reset_expansion: false,
                    admin_override: true,
                    admin_lock_type: 'no_lock'
                  }
                ])

      use_chain(Mail::VpsDatasetExpanded, args: [exp]) if exp.enable_notifications

      append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
        t.just_create(dataset_expansion_history)
        t.edit(exp, added_space: exp.added_space + dataset_expansion_history.added_space)
      end

      dataset_expansion_history
    end
  end
end
