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
      string :addr, label: 'Address', desc: 'Address itself', db_name: :ip_addr
      integer :prefix, label: 'Prefix'
      integer :size, label: 'Size'
      integer :max_tx, label: 'Max tx', desc: 'Maximum output throughput'
      integer :max_rx, label: 'Max rx', desc: 'Maximum input throughput'
    end

    params(:common) do
      use :filters, include: %i(ip_address addr)
    end

    params(:all) do
      use :id
      use :common
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List IP addresses'

      input do
        use :filters
        patch :user, desc: 'Filter by owner'
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        input whitelist: %i(location network version role addr prefix vps
                            ip_address limit offset)
        allow
      end

      def query
        ips = ::HostIpAddress

        %i(prefix size max_tx max_rx).each do |filter|
          next unless input.has_key?(filter)

          ips = ips.joins(:ip_address).where(
            ip_addresses: {filter => input[filter]},
          )
        end

        if input[:network]
          ips = ips.joins(:ip_address).where(
            ip_addresses: {network_id: input[:network].id},
          )
        end

        if input[:location]
          ips = ips.joins(ip_address: :network).where(
            networks: {location_id: input[:location].id},
          )
        end

        if input[:ip_address]
          ips = ips.where(ip_address: input[:ip_address])
        end

        if input[:network_interface]
          ips = ips.joins(:ip_address).where(
            ip_addresses: {network_interface_id: input[:network_interface].id},
          )
        end

        if input[:version]
          ips = ips.joins(ip_address: :network).where(
            networks: {ip_version: input[:version]},
          )
        end

        if input[:role]
          ips = ips.joins(ip_address: :network).where(
            networks: {role: ::Network.roles[input[:role]]},
          )
        end

        if current_user.role != :admin
          ips = ips.joins(ip_address: :network).joins(
            'LEFT JOIN network_interfaces my_netifs
             ON my_netifs.id = ip_addresses.network_interface_id'
          ).joins(
            'LEFT JOIN vpses my_vps ON my_vps.id = my_netifs.vps_id'
          ).where(
            networks: {role: [
              ::Network.roles[:public_access],
              ::Network.roles[:private_access],
            ]},
          ).where(
            'ip_addresses.user_id = ?
             OR
            (ip_addresses.network_interface_id IS NOT NULL AND my_vps.user_id = ?)',
            current_user.id, current_user.id, current_user.id
          ).order('host_ip_addresses.id ASC')
        end

        ips
      end

      def count
        query.count
      end

      def exec
        with_includes(query)
          .order('ip_addresses.id')
          .limit(input[:limit])
          .offset(input[:offset])
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show interface IP address'

      output do
        use :all
      end

      authorize do |u|
        allow
      end

      def prepare
        if current_user.role == :admin
          @ip = ::HostIpAddress.find(params[:host_ip_address_id])

        else
          @ip = ::HostIpAddress.joins(:ip_address).joins(
            'LEFT JOIN network_interfaces my_netifs
             ON my_netifs.id = ip_addresses.network_interface_id'
          ).joins(
            'LEFT JOIN vpses my_vps ON my_vps.id = my_netifs.vps_id'
          ).where(
            'ip_addresses.user_id = ?
             OR
            (ip_addresses.network_interface_id IS NOT NULL AND my_vps.user_id = ?)',
            current_user.id, current_user.id
          ).where(id: params[:host_ip_address_id]).take!
        end
      end

      def exec
        @ip
      end
    end

    class Assign < HaveAPI::Action
      desc 'Assign the address to an interface'
      route ':%{resource}_id/assign'
      http_method :post
      blocking true

      output do
        use :all
      end

      authorize do |u|
        allow
      end

      def exec
        host = ::HostIpAddress.find(params[:host_ip_address_id])
        netif = host.ip_address.network_interface

        if netif.nil?
          error("#{host.ip_address} is not assigned to any interface")

        elsif current_user.role != :admin && ( \
                (host.ip_address.user_id && host.ip_address.user_id != current_user.id) \
                || (netif && netif.vps.user_id != current_user.id) \
              )
          error('access denied')
        end

        maintenance_check!(netif.vps)

        @chain, _ = netif.add_host_address(host)
        host
      end

      def state_id
        @chain.id
      end
    end

    class Free < HaveAPI::Action
      desc 'Remove the address from its interface'
      route ':%{resource}_id/free'
      http_method :post
      blocking true

      output do
        use :all
      end

      authorize do |u|
        allow
      end

      def exec
        host = ::HostIpAddress.find(params[:host_ip_address_id])
        netif = host.ip_address.network_interface

        if netif.nil?
          error("#{host.ip_address} is not assigned to any interface")

        elsif current_user.role != :admin && ( \
                (host.ip_address.user_id && host.ip_address.user_id != current_user.id) \
                || (netif && netif.vps.user_id != current_user.id) \
              )
          error('access denied')
        end

        maintenance_check!(netif.vps)

        @chain, _ = netif.remove_host_address(host)
        host
      end

      def state_id
        @chain.id
      end
    end
  end
end
