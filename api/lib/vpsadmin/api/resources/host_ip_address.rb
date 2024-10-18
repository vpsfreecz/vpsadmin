module VpsAdmin::API::Resources
  class HostIpAddress < HaveAPI::Resource
    model ::HostIpAddress
    desc 'Manage interface IP addresses'

    params(:id) do
      id :id, label: 'ID', desc: 'IP address ID'
    end

    params(:filters) do
      resource IpAddress, value_label: :addr
      resource NetworkInterface, value_label: :name
      resource VPS, label: 'VPS',
                    desc: 'VPS this IP is assigned to, can be null',
                    value_label: :hostname
      integer :version, label: 'IP version', desc: '4 or 6'
      resource Network, label: 'Network', value_label: :address
      resource Location, label: 'Location',
                         desc: 'Location this IP address is available in'
      resource User, label: 'User',
                     value_label: :login
      string :role, choices: ::Network.roles.keys
      string :purpose, choices: ::Network.purposes.keys
      string :addr, label: 'Network address', db_name: :ip_addr
      integer :prefix, label: 'Prefix'
      integer :size, label: 'Size'
      bool :assigned, label: 'Assigned'
      bool :routed, label: 'Routed'
    end

    params(:common) do
      use :filters, include: %i[ip_address addr assigned]
    end

    params(:all) do
      use :id
      use :common
      bool :user_created
      string :reverse_record_value
      patch :addr, label: 'Address'
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List IP addresses'

      input do
        use :filters
        patch :user, desc: 'Filter by owner'
        string :order, choices: %w[asc interface], default: 'asc', fill: true
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        input whitelist: %i[location network version role purpose addr prefix vps
                            network_interface ip_address assigned routed order
                            limit offset]
        allow
      end

      def query
        ips = ::HostIpAddress.joins(ip_address: :network)

        %i[prefix size].each do |filter|
          next unless input.has_key?(filter)

          ips = ips.where(
            ip_addresses: { filter => input[filter] }
          )
        end

        if input[:network]
          ips = ips.where(
            ip_addresses: { network_id: input[:network].id }
          )
        end

        if input[:location]
          locs = ::LocationNetwork.where(location: input[:location]).pluck(:network_id)
          ips = ips.where(networks: { id: locs })
        end

        if input.has_key?(:vps)
          ips = ips.joins(ip_address: :network_interface).where(
            network_interfaces: { vps_id: input[:vps] && input[:vps].id }
          )
        end

        ips = ips.where(ip_address: input[:ip_address]) if input[:ip_address]

        if input[:network_interface]
          ips = ips.where(
            ip_addresses: { network_interface_id: input[:network_interface].id }
          )
        end

        ips = ips.where(networks: { ip_version: input[:version] }) if input[:version]

        ips = ips.where(networks: { role: ::Network.roles[input[:role]] }) if input[:role]

        ips = ips.where(networks: { purpose: ::Network.purposes[input[:purpose]] }) if input[:purpose]

        ips = ips.where(ip_addresses: { ip_addr: input[:addr] }) if input[:addr]

        %i[prefix size].each do |filter|
          next unless input[filter]

          ips = ips.where(ip_addresses: { filter => input[:filter] })
        end

        if current_user.role == :admin && input.has_key?(:user)
          user_id = input[:user] && input[:user].id

          ips = ips.joins(
            'LEFT JOIN network_interfaces my_netifs
             ON my_netifs.id = ip_addresses.network_interface_id'
          ).joins(
            'LEFT JOIN vpses my_vps ON my_vps.id = my_netifs.vps_id'
          ).where(
            'ip_addresses.user_id = ?
             OR
            (ip_addresses.network_interface_id IS NOT NULL AND my_vps.user_id = ?)',
            user_id, user_id
          )
        end

        if input.has_key?(:assigned) && !input[:assigned].nil?
          ips = if input[:assigned]
                  ips.where.not(order: nil)
                else
                  ips.where(order: nil)
                end
        end

        if input.has_key?(:routed) && !input[:routed].nil?
          ips = if input[:routed]
                  ips.where.not(ip_addresses: { network_interface_id: nil })
                else
                  ips.where(ip_addresses: { network_interface_id: nil })
                end
        end

        if current_user.role != :admin
          ips = ips.joins(ip_address: { network_interface: :vps }).where(
            'ip_addresses.user_id = ? OR vpses.user_id = ?',
            current_user.id, current_user.id
          )
        end

        ips
      end

      def count
        query.count
      end

      def exec
        with_includes(query)
          .order(Arel.sql(order_col))
          .limit(input[:limit])
          .offset(input[:offset])
      end

      protected

      def order_col
        case input[:order]
        when 'interface'
          'networks.ip_version, host_ip_addresses.`order`'
        else
          'host_ip_addresses.id'
        end
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show interface IP address'

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      def prepare
        @ip = if current_user.role == :admin
                ::HostIpAddress.find(params[:host_ip_address_id])

              else
                ::HostIpAddress.joins(:ip_address).joins(
                  'LEFT JOIN network_interfaces my_netifs
             ON my_netifs.id = ip_addresses.network_interface_id'
                ).joins(
                  'LEFT JOIN vpses my_vps ON my_vps.id = my_netifs.vps_id'
                ).joins(
                  'LEFT JOIN exports my_export ON my_export.id = my_netifs.export_id'
                ).where(
                  'ip_addresses.user_id = ?
             OR
             (
               ip_addresses.network_interface_id IS NOT NULL
               AND
               (my_vps.user_id = ? OR my_export.user_id = ?)
             )',
                  current_user.id, current_user.id, current_user.id
                ).where(id: params[:host_ip_address_id]).take!
              end
      end

      def exec
        @ip
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Add host IP address'

      input do
        use :common, include: %i[ip_address addr]

        %i[ip_address addr].each do |v|
          patch v, required: true
        end
      end

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      def exec
        ip = input[:ip_address]

        error('access denied') if current_user.role != :admin && ip.current_owner != current_user

        VpsAdmin::API::Operations::HostIpAddress::Create.run(ip, input[:addr])
      rescue VpsAdmin::API::Exceptions::OperationError => e
        error("create failed: #{e.message}")
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update host IP address'
      blocking true

      input do
        use :all, include: %i[reverse_record_value]
      end

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      def exec
        host = ::HostIpAddress.find(params[:host_ip_address_id])

        error('access denied') if current_user.role != :admin && host.current_owner != current_user

        ptr_content = input.fetch(:reverse_record_value, '').strip

        unless ptr_content.empty?
          ptr_content << '.' unless ptr_content.end_with?('.')

          if /\A((?!-)[A-Za-z0-9-]{1,63}(?<!-)\.)+[A-Za-z]{2,63}\.\z/ !~ ptr_content
            error('invalid reverse record value', { reverse_record_value: ['not a valid domain'] })
          end
        end

        @chain, ret = VpsAdmin::API::Operations::HostIpAddress::Update.run(
          host,
          { reverse_record_value: ptr_content }
        )
        ret
      rescue VpsAdmin::API::Exceptions::OperationError => e
        error("update failed: #{e.message}")
      end

      def state_id
        @chain && @chain.id
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete host IP address'
      blocking true

      authorize do |_u|
        allow
      end

      def exec
        host = ::HostIpAddress.find(params[:host_ip_address_id])

        error('access denied') if current_user.role != :admin && host.current_owner != current_user

        @chain, = VpsAdmin::API::Operations::HostIpAddress::Destroy.run(host)
        ok
      rescue VpsAdmin::API::Exceptions::OperationError => e
        error("delete failed: #{e.message}")
      end

      def state_id
        @chain && @chain.id
      end
    end

    class Assign < HaveAPI::Action
      desc 'Assign the address to an interface'
      route '{%{resource}_id}/assign'
      http_method :post
      blocking true

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      include VpsAdmin::API::Lifetimes::ActionHelpers

      def exec
        host = ::HostIpAddress.find(params[:host_ip_address_id])
        netif = host.ip_address.network_interface

        if netif.nil?
          error("#{host.ip_address} is not assigned to any interface")

        elsif current_user.role != :admin && host.current_owner != current_user
          error('access denied')

        elsif host.assigned?
          error("#{host.ip_addr} address is already assigned")
        end

        maintenance_check!(netif.vps)
        object_state_check!(netif.vps, netif.vps.user)

        @chain, = netif.add_host_address(host)
        host
      end

      def state_id
        @chain.id
      end
    end

    class Free < HaveAPI::Action
      desc 'Remove the address from its interface'
      route '{%{resource}_id}/free'
      http_method :post
      blocking true

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      include VpsAdmin::API::Lifetimes::ActionHelpers

      def exec
        host = ::HostIpAddress.find(params[:host_ip_address_id])
        netif = host.ip_address.network_interface

        if netif.nil?
          error("#{host.ip_address} is not routed to any interface")

        elsif current_user.role != :admin && host.current_owner != current_user
          error('access denied')

        elsif host.routed_via_addresses.any?
          error('one or more networks are routed via this address')
        end

        maintenance_check!(netif.vps)
        object_state_check!(netif.vps, netif.vps.user)

        @chain, = netif.remove_host_address(host)
        host
      rescue VpsAdmin::API::Exceptions::IpAddressNotAssigned
        error("#{host.ip_addr} is not assigned to any interface")
      end

      def state_id
        @chain.id
      end
    end
  end
end
