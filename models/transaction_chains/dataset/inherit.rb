module TransactionChains
  class Dataset::Inherit < ::TransactionChain
    label 'Inherit dataset properties'

    def link_chain(dataset_in_pool, properties)
      lock(dataset_in_pool)

      chain = self
      props = {}

      dataset_in_pool.dataset_properties.where(name: properties).each do |p|
        props[p.name.to_sym] = p unless p.inherited
      end

      append(Transactions::Storage::InheritProperty, args: [dataset_in_pool, props]) do

        props.each do |name, p|
          if p.parent
            v = p.parent.value

          else
            v = VpsAdmin::API::DatasetProperties.property(name).meta[:default]
          end

          yml = YAML.dump(v)

          edit(p, inherited: true, value: yml)
          chain.edit_children(self, p, yml)
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
