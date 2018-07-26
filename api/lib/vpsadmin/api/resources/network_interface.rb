module VpsAdmin::API::Resources
  class NetworkInterface < HaveAPI::Resource
    desc 'Manage VPS network interfaces'
    model ::NetworkInterface

    params(:all) do
      id :id, label: 'ID', desc: 'Interface ID'
      resource VPS, label: 'VPS',
        desc: 'VPS the interface is assigned to, can be null',
        value_label: :hostname
      string :name
      string :type, choices: ::NetworkInterface.kinds.keys.map(&:to_s),
        db_name: :kind
      string :mac, label: 'MAC Address'
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List network interfaces'

      input do
        resource VPS, label: 'VPS',
          desc: 'VPS the interface is assigned to, can be null',
          value_label: :hostname
        resource Location, label: 'Location',
          desc: 'Location this IP address is available in'
        resource User, label: 'User', value_label: :login
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict vpses: {user_id: u.id}
        input whitelist: %i(vps location limit offset)
        allow
      end

      def query
        q = ::NetworkInterface.joins(:vps).where(with_restricted)
        q = q.where(vps: input[:vps]) if input[:vps]

        if input[:location]
          q = q.joins(vps: :node).where(nodes: {location_id: input[:location].id})
        end

        q = q.where(vpses: {user_id: input[:user].id}) if input[:user]
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
      desc 'Show a network interface'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict vpses: {user_id: u.id}
        allow
      end

      def prepare
        @netif = ::NetworkInterface.joins(:vps).find_by!(with_restricted(
          network_interfaces: {id: params[:network_interface_id]},
        ))
      end

      def exec
        @netif
      end
    end
  end
end
