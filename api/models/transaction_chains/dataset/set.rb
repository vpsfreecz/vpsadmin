module TransactionChains
  class Dataset::Set < ::TransactionChain
    label 'Set properties'

    # @param dataset_in_pool [DatasetInPool]
    # @param properties [Hash<Symbol, any>]
    # @param opts [Hash]
    # @option opts [Boolean] :admin_override
    # @option opts [String] :admin_lock_type
    # @option opts [Boolean] :reset_expansion
    def link_chain(dataset_in_pool, properties, opts)
      lock(dataset_in_pool)
      concerns(:affect, [dataset_in_pool.dataset.class.name, dataset_in_pool.dataset_id])

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

      append_t(Transactions::Storage::SetDataset, args: [dataset_in_pool, props]) do |t|

        props.each_value do |p|
          edit_children(t, p[0], YAML.dump(p[1]))
          t.edit(p[0], inherited: false)
        end

        t.edit(use, value: use.value) if use

        if opts.fetch(:reset_expansion, true) \
           && props.has_key?(:refquota) \
           && dataset_in_pool.dataset.dataset_expansion
          t.edit(dataset_in_pool.dataset, dataset_expansion_id: nil)
          t.edit(dataset_in_pool.dataset.dataset_expansion, state: ::DatasetExpansion.states[:resolved])
        end

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
