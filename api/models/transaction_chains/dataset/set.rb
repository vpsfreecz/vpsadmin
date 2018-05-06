module TransactionChains
  class Dataset::Set < ::TransactionChain
    label 'Set properties'

    def link_chain(dataset_in_pool, properties, opts)
      lock(dataset_in_pool)
      concerns(:affect, [dataset_in_pool.dataset.class.name, dataset_in_pool.dataset_id])

      chain = self
      props = {}

      dataset_in_pool.dataset_properties.where(name: properties.keys).each do |p|
        props[p.name.to_sym] = [
          p,
          properties[p.name.to_sym]
        ]
      end

      use = nil

      if props[:refquota] && dataset_in_pool.pool.refquota_check
        use = dataset_in_pool.reallocate_resource!(
          :diskspace,
          properties[:refquota],
          user: dataset_in_pool.dataset.user,
          override: opts[:admin_override],
          lock_type: opts[:admin_lock_type]
        )

      # Quota is checked only for top-level dataset
      elsif props[:quota] && dataset_in_pool.dataset.parent_id.nil?
        use = dataset_in_pool.reallocate_resource!(
          :diskspace,
          properties[:quota],
          user: dataset_in_pool.dataset.user,
          override: opts[:admin_override],
          lock_type: opts[:admin_lock_type]
        )
      end

      append(Transactions::Storage::SetDataset, args: [dataset_in_pool, props]) do

        props.each_value do |p|
          chain.edit_children(self, p[0], YAML.dump(p[1]))
          edit(p[0], inherited: false)
        end

        edit(use, value: use.value) if use

      end
    end

    def edit_children(confirm, parent, v)
      if parent.inheritable?
        parent.children.each do |child|
          next unless child.inherited

          edit_children(confirm, child, v)
          confirm.edit(child, value: v)
        end
      end

      confirm.edit(parent, value: v)
    end
  end
end
