module TransactionChains
  class Dataset::RefquotaSet < ::TransactionChain
    label 'Set refquota'

    def link_chain(refquota_dip, dip, refquota, creation = false)
      parent_refquota = refquota_dip.property_refquota
      old_refquota = parent_refquota.value

      # Dataset is being created right now, just subtract the refquota
      # from refquota_dip and run checks.
      if creation
        parent_refquota.value -= refquota
        zero_check(parent_refquota)
        parent_refquota.save!

        check_subtree(refquota_dip)

      else
        diff = dip.refquota - refquota

        parent_refquota.value += diff
        zero_check(parent_refquota)
        parent_refquota.save!
        dip.refquota = refquota

        if dip.dataset.depth > refquota_dip.dataset.depth
          check_subtree(refquota_dip)

        elsif dip.dataset.depth < refquota_dip.dataset.depth
          check_subtree(dip)

        else # equal depth
          check_subtree(dip.parent.primary_dataset_in_pool!)
        end
      end

      new_refquota = parent_refquota.value
      parent_refquota.value = old_refquota
      parent_refquota.save!

      append(Transactions::Storage::SetDataset,
             args: [refquota_dip, {refquota: [parent_refquota, new_refquota]}]) do
        edit(parent_refquota, value: YAML.dump(new_refquota))
      end
    end

    protected
    def zero_check(p)
      if p.value <= 0
        raise VpsAdmin::API::Exceptions::RefquotaCheckFailed, "refquota limit exceeded for #{p.dataset.full_name}"
      end
    end

    def check_subtree(dip)
      dip.dataset.subtree.arrange.each do |k, v|
        recursive_check(k, v)
      end
    end

    def recursive_check(dataset, children)
      refquota = dataset.primary_dataset_in_pool!.refquota
      sum = 0

      children.each_value do |child|
        if child.is_a?(::Dataset)
          sum += child.primary_dataset_in_pool!.refquota

          if sum > refquota
            raise VpsAdmin::API::Exceptions::RefquotaCheckFailed, "refquota limit exceeded for #{dataset.full_name}"
          end
        end
      end

      children.each do |k, v|
        recursive_check(k, v) if v.is_a?(::Hash)
      end
    end
  end
end
