module VpsAdmin::API::Resources
  class Network < HaveAPI::Resource
    desc 'Manage networks'
    model ::Network

    params(:ro) do
      integer :size, desc: 'Number of possible host IP addresses'
      integer :used, desc: 'Number of IP addresses present in vpsAdmin'
      integer :assigned, desc: 'Number of IP addresses assigned to VPSes'
      integer :owned, desc: 'Number of IP addresses owned by some users'
    end

    params(:common) do
      string :label
      integer :ip_version
      string :address
      integer :prefix
      string :role, choices: ::Network.roles.keys
      bool :managed
      string :split_access, choices: ::Network.split_accesses.keys
      integer :split_prefix
      bool :autopick
      string :purpose, choices: ::Network.purposes.keys
    end

    params(:all) do
      id :id
      use :common
      use :ro
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List networks'

      input do
        resource Location
        use :common, include: %i(purpose)
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        output whitelist: %i(
            id address prefix ip_version role split_access split_prefix purpose
          )
        allow
      end

      def query
        q = ::Network.all

        if input[:location]
          q = q.joins(:location_networks).where(
            location_networks: {location_id: input[:location].id},
          )
        end

        q = q.where(purpose: input[:purpose]) if input[:purpose]
        q
      end

      def count
        query.count
      end

      def exec
        with_includes(query).offset(input[:offset]).limit(input[:limit])
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show a network'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        output whitelist: %i(
            id address prefix ip_version role split_access split_prefix purpose
          )
        allow
      end

      def prepare
        @net = ::Network.find(params[:network_id])
      end

      def exec
        @net
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Add a new network'
      blocking true

      input do
        use :common
        patch :address, required: true
        patch :prefix, required: true
        patch :ip_version, required: true
        patch :role, required: true
        patch :managed, required: true
        patch :split_prefix, required: true
        patch :purpose, required: true

        bool :add_ip_addresses, default: false,
            desc: 'Add all IP addresses from this network to the database now'
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        add_ips = input.delete(:add_ip_addresses)

        @chain, net = ::Network.register!(input, add_ips: add_ips)
        net

      rescue ActiveRecord::RecordInvalid => e
        error('create failed', e.record.errors.to_hash)

      rescue ActiveRecord::RecordNotUnique
        error('this network already exists')
      end

      def state_id
        @chain.id
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update a network'

      input do
        use :common
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        net = ::Network.find(params[:network_id])
        net.update!(input)
        net

      rescue ActiveRecord::RecordInvalid => e
        error('update failed', e.record.errors.to_hash)

      rescue ActiveRecord::RecordNotUnique
        error('this network already exists')
      end
    end

    class AddAddresses < HaveAPI::Action
      desc 'Add IP addresses to a managed network'
      route '{%{resource}_id}/add_addresses'
      http_method :post

      input do
        integer :count, required: true, number: {
          min: 1,
        }
        resource User, desc: 'Owner of new IP addresses'
        resource Environment, desc: 'Environment to which the addresses are charged'
      end

      output(:hash) do
        integer :count, desc: 'Number of added IP addresses'
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        net = ::Network.find(params[:network_id])

        unless net.managed
          error('this action can be used only on managed networks')
        end

        {
          count: net.add_ips(
            input[:count],
            user: input[:user],
            environment: input[:environment],
          ).count,
        }

      rescue ActiveRecord::RecordInvalid => e
        error('add failed', e.record.errors.to_hash)
      end
    end
  end
end
