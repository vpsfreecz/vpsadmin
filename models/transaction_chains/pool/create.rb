module TransactionChains
  class Pool::Create < ::TransactionChain
    label 'Create'

    def link_chain(pool, properties)
      lock(pool.node)

      pool.save!
      
      lock(pool)
      concerns(:affect, [pool.class.name, pool.id])

      append(Transactions::Storage::CreatePool, args: [pool, properties]) do
        VpsAdmin::API::DatasetProperties::Registrator.properties.each do |name, p|
          create(::DatasetProperty.create!(
              pool: pool,
              name: name,
              value: properties.has_key?(name) ? properties[name] : p.meta[:default],
              inherited: false,
              confirmed: ::DatasetProperty.confirmed(:confirm_create)
          ))
        end
      end

      pool
    end
  end
end
