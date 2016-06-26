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
      resource Location
      integer :ip_version
      string :address
      integer :prefix
      string :role, choices: ::Network.roles.keys
      bool :partial
      bool :managed
    end

    params(:all) do
      id :id
      use :common
      use :ro
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List networks'

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        output whitelist: %i(location ip_version)
        allow
      end

      def query
        ::Network.all
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
        output whitelist: %i(location ip_version)
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

      input do
        use :common
        patch :location, required: true
        patch :address, required: true
        patch :prefix, required: true
        patch :ip_version, required: true
        patch :role, required: true
        patch :managed, required: true
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        ::Network.create!(input)

      rescue ActiveRecord::RecordInvalid => e
        error('create failed', e.record.errors.to_hash)

      rescue ActiveRecord::RecordNotUnique
        error('this network already exists')
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
  end
end
