module TransactionChains
  class Dataset::Set < ::TransactionChain
    label 'Set dataset properties'

    def link_chain(dataset_in_pool, properties)
      lock(dataset_in_pool)

      chain = self
      props = {}

      dataset_in_pool.dataset_properties.where(name: properties.keys).each do |p|
        props[p.name.to_sym] = [
            p,
            properties[p.name.to_sym]
        ]
      end

      append(Transactions::Storage::SetDataset, args: [dataset_in_pool, props]) do

        props.each_value do |p|
          chain.edit_children(self, p[0], YAML.dump(p[1]))
          edit(p[0], inherited: false)
        end

      end
    end

    def edit_children(confirm, parent, v)
      parent.children.each do |child|
        next unless child.inherited

        edit_children(confirm, child, v)
        confirm.edit(child, value: v)
      end

      confirm.edit(parent, value: v)
    end
  end
end
