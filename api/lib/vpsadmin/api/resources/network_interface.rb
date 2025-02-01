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
      integer :max_tx, label: 'Max outgoing data throughput'
      integer :max_rx, label: 'Max incoming data throughput'
      bool :enable
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
        restrict vpses: { user_id: u.id }
        input whitelist: %i[vps location limit from_id]
        allow
      end

      def query
        q = ::NetworkInterface.joins(:vps).where(with_restricted)
        q = q.where(vps: input[:vps]) if input[:vps]

        q = q.joins(vps: :node).where(nodes: { location_id: input[:location].id }) if input[:location]

        q = q.where(vpses: { user_id: input[:user].id }) if input[:user]
        q
      end

      def count
        query.count
      end

      def exec
        with_pagination(with_includes(query))
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show a network interface'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict vpses: { user_id: u.id }
        allow
      end

      def prepare
        @netif = ::NetworkInterface.joins(:vps).find_by!(with_restricted(
                                                           network_interfaces: { id: params[:network_interface_id] }
                                                         ))
      end

      def exec
        @netif
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Modify a network interface'
      blocking true

      input do
        use :all, include: %i[name max_tx max_rx enable]
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        input whitelist: %i[name]
        restrict vpses: { user_id: u.id }
        allow
      end

      include VpsAdmin::API::Maintainable::Check
      include VpsAdmin::API::Lifetimes::ActionHelpers

      def exec
        netif = ::NetworkInterface.joins(:vps).find_by!(with_restricted(
                                                          network_interfaces: { id: params[:network_interface_id] }
                                                        ))

        ok!(netif) if input.empty?

        error!('veth renaming is not available on this node') if input[:name] && !netif.vps.node.vpsadminos?

        maintenance_check!(netif.vps)
        object_state_check!(netif.vps, netif.vps.user)

        @chain, ret = TransactionChains::NetworkInterface::Update.fire(netif, input)
        ret
      end

      def state_id
        @chain && @chain.id
      end
    end
  end
end
