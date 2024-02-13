module VpsAdmin::API::Resources
  class LocationNetwork < HaveAPI::Resource
    desc 'Manage location networks'
    model ::LocationNetwork

    params(:ro) do
      resource Location
      resource Network, value_label: :address
    end

    params(:rw) do
      bool :primary
      integer :priority
      bool :autopick
      bool :userpick
    end

    params(:all) do
      id :id
      use :ro
      use :rw
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List location networks'

      input do
        use :ro
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def query
        q = ::LocationNetwork.all
        q = q.where(location: input[:location]) if input[:location]
        q = q.where(network: input[:network]) if input[:network]
        q
      end

      def count
        query.count
      end

      def exec
        q = with_includes(query).offset(input[:offset]).limit(input[:limit])

        if input[:location] && !input[:network]
          q.order('location_networks.priority')
        else
          q.order('location_networks.location_id, location_networks.priority')
        end
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show a location network'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def prepare
        @net = ::LocationNetwork.find(params[:location_network_id])
      end

      def exec
        @net
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Add network to a location'

      input do
        use :ro
        use :rw
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        VpsAdmin::API::Operations::LocationNetwork::Create.run(input)
      rescue ActiveRecord::RecordInvalid => e
        error('create failed', e.record.errors.to_hash)
      rescue ActiveRecord::RecordNotUnique
        error('this network already exists in the selected location')
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update a location network'

      input do
        use :rw
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        VpsAdmin::API::Operations::LocationNetwork::Update.run(
          ::LocationNetwork.find(params[:location_network_id]),
          input
        )
      rescue ActiveRecord::RecordInvalid => e
        error('update failed', e.record.errors.to_hash)
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Remove network from a location'

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        VpsAdmin::API::Operations::LocationNetwork::Delete.run(
          ::LocationNetwork.find(params[:location_network_id])
        )
        ok
      end
    end
  end
end
