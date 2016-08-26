module VpsAdmin::API::Resources
  class IpRange < HaveAPI::Resource
    desc 'Manage IP ranges'
    model ::IpRange

    params(:ro) do
      integer :size, desc: 'Number of possible host IP addresses'
      integer :assigned, desc: 'Number of IP addresses assigned to VPSes'
      integer :owned, desc: 'Number of IP addresses owned by some users'
    end

    params(:common) do
      string :label
      resource Network
      resource User, value_label: :login
      string :address
      integer :prefix
    end

    params(:all) do
      id :id
      use :common
      use :ro
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List IP ranges'

      input do
        resource Network
        resource Location
        integer :ip_version
        resource User
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        input blacklist: %i(user)
        output blacklist: %i(user)
        restrict user: u
        allow
      end

      def query
        q = ::IpRange.where(with_restricted)
        q = q.children_of(input[:network]) if input[:network]

        %i(location ip_version user).each do |f|
          q = q.where(f => input[f]) if input.has_key?(f)
        end

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
      desc 'Show an IP range'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        output blacklist: %i(user)
        restrict user: u
        allow
      end

      def prepare
        @range = ::IpRange.find_by!(with_restricted(
            id: params[:ip_range_id]
        ))
      end

      def exec
        @range
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create an IP range'

      input do
        resource Network, required: true
        resource User
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        input whitelist: %i(network)
        allow
      end

      def exec
        net = input[:network]
        opts = {}

        if current_user.role == :admin
          opts[:user] = input[:user]

        else
          if net.split_access == 'no_access'
            error('this network cannot be split')

          elsif net.split_access == 'owner_split' && net.user != current_user
            error('access denied')
          end

          opts[:user] = current_user
        end

        ::IpRange.from_network(net, opts)

      rescue ActiveRecord::RecordInvalid => e
        error('create failed', e.record.errors.to_hash)
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Change an IP range'

      input do
        resource User, required: true
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        range = ::IpRange.find(params[:ip_range_id])
        
        if range.user == input[:user]
          range

        else
          range.chown(input[:user])
          range
        end

      rescue RuntimeError => e
        error(e.message)
      end
    end
  end
end
