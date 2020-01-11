class VpsAdmin::API::Resources::IpAddress < HaveAPI::Resource
  model ::IpAddress
  desc 'Manage IP addresses'

  params(:id) do
    id :id, label: 'ID', desc: 'IP address ID'
  end

  params(:shaper) do
    integer :max_tx, label: 'Max tx', desc: 'Maximum output throughput'
    integer :max_rx, label: 'Max rx', desc: 'Maximum input throughput'
  end

  params(:filters) do
    resource VpsAdmin::API::Resources::NetworkInterface, value_label: :name
    resource VpsAdmin::API::Resources::VPS, label: 'VPS',
            desc: 'VPS this IP is assigned to, can be null',
            value_label: :hostname
    integer :version, label: 'IP version', desc: '4 or 6'
    resource VpsAdmin::API::Resources::Network, label: 'Network', value_label: :address
    resource VpsAdmin::API::Resources::Location, label: 'Location',
              desc: 'Location this IP address is available in'
    resource VpsAdmin::API::Resources::User, label: 'User',
             value_label: :login
    string :role, choices: ::Network.roles.keys
    string :purpose, choices: ::Network.purposes.keys
    string :addr, label: 'Address', desc: 'Address itself', db_name: :ip_addr
    integer :prefix, label: 'Prefix'
    integer :size, label: 'Size'
    use :shaper
  end

  params(:common) do
    use :filters, include: %i(network prefix size network_interface user addr)
    resource VpsAdmin::API::Resources::HostIpAddress, name: :route_via, value_label: :addr
    use :shaper
    integer :class_id, label: 'Class id', desc: 'Class id for shaper'
  end

  params(:all) do
    use :id
    use :common
    resource VpsAdmin::API::Resources::Environment,
      name: :charged_environment,
      label: 'Charged environment'
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
      input whitelist: %i(location network version role purpose addr prefix vps
                          network_interface limit offset)
      output blacklist: %i(class_id)
      allow
    end

    example do
      request({
        vps: 101
      })
      response([{
        id: 10,
        vps: {
          id: 101,
          hostname: 'myvps'
        },
        version: 4,
        location: {
          id: 1,
          label: 'The Location'
        },
        addr: '192.168.0.50'
      }])
      comment 'List IP addresses assigned to VPS with ID 101.'
    end

    def query
      ips = ::IpAddress

      %i(prefix network network_interface user addr max_tx max_rx).each do |filter|
        next unless input.has_key?(filter)

        ips = ips.where(
          filter => input[filter],
        )
      end

      if input.has_key?(:vps)
        ips = ips.joins(:network_interface).where(
          network_interfaces: {vps_id: input[:vps] && input[:vps].id},
        )
      end

      if input[:location]
        locs = ::LocationNetwork.where(location: input[:location]).pluck(:network_id)
        ips = ips.joins(:network).where(networks: {id: locs})
      end

      if input[:version]
        ips = ips.joins(:network).where(networks: {ip_version: input[:version]})
      end

      if input[:role]
        ips = ips.joins(:network).where(networks: {role: ::Network.roles[input[:role]]})
      end

      if input[:purpose]
        ips = ips.joins(:network).where(networks: {purpose: ::Network.roles[input[:purpose]]})
      end

      if current_user.role != :admin
        ips = ips.joins(:network).joins(
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
            OR (ip_addresses.network_interface_id IS NOT NULL AND my_vps.user_id = ?)
            OR (ip_addresses.user_id IS NULL AND ip_addresses.network_interface_id IS NULL)',
          current_user.id, current_user.id
        ).order('ip_addresses.user_id DESC, ip_addresses.id ASC')
      end

      ips
    end

    def count
      query.count
    end

    def exec
      with_includes(query).order('ip_addresses.id').limit(input[:limit]).offset(input[:offset])
    end
  end

  class Show < HaveAPI::Actions::Default::Show
    desc 'Show IP address'

    output do
      use :all
    end

    authorize do |u|
      allow
    end

    def prepare
      if current_user.role == :admin
        @ip = ::IpAddress.find(params[:ip_address_id])
      else
        @ip = ::IpAddress.where(
          'user_id = ? OR user_id IS NULL',
          current_user.id
        ).where(id: params[:ip_address_id]).take!

        @ip = ::IpAddress.joins(
          'LEFT JOIN network_interfaces my_netifs
           ON my_netifs.id = ip_addresses.network_interface_id'
        ).joins(
          'LEFT JOIN vpses my_vps ON my_vps.id = my_netifs.vps_id'
        ).where(
          'ip_addresses.user_id = ?
           OR (ip_addresses.network_interface_id IS NOT NULL AND my_vps.user_id = ?)
           OR (ip_addresses.user_id IS NULL AND ip_addresses.network_interface_id IS NULL)',
          current_user.id, current_user.id
        ).where(id: params[:ip_address_id]).take!
      end
    end

    def exec
      @ip
    end
  end

  class Create < HaveAPI::Actions::Default::Create
    desc 'Add an IP address'

    input do
      use :common, exclude: %i(vps class_id version)
      patch :addr, required: true
      patch :network, required: true
    end

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
    end

    def exec
      addr = ::IPAddress.parse(input[:addr]) # gem

      if input[:user]
        if !input[:location]
          error('provide location together with user')
        elsif input[:network].locations.include?(input[:location])
          error('network is not available in selected location')
        end
      end

      ::IpAddress.register(addr, input.merge(prefix: addr.prefix)) # model

    rescue ArgumentError => e
      error(e.message, {addr: ['not a valid IP address']})

    rescue ::ActiveRecord::RecordInvalid => e
      error('create failed', e.record.errors.to_hash)
    end
  end

  class Update < HaveAPI::Actions::Default::Update
    desc 'Update IP address'
    blocking true

    input do
      use :shaper
      use :filters, include: %i(user)
      resource VpsAdmin::API::Resources::Environment
    end

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
    end

    def exec
      ip = ::IpAddress.find(params[:ip_address_id])

      if input.has_key?(:user) && ip.user != input[:user]
        # Check if the IP is assigned to a VPS in an environment with IP ownership
        if ip.network_interface && ip.network_interface.vps.node.location.environment.user_ip_ownership
          error('cannot chown IP while it belongs to a VPS')
        end
      end

      if input[:user] && !input.has_key?(:environment)
        error('choose environment')
      end

      @chain, _ = ip.do_update(input)
      ip

    rescue ActiveRecord::RecordInvalid => e
      error('update failed', e.record.errors.to_hash)
    rescue VpsAdmin::API::Exceptions::IpAddressInvalidLocation => e
      error(e.message)
    end

    def state_id
      @chain.empty? ? nil : @chain.id
    end
  end

  class Assign < HaveAPI::Action
    desc 'Route the address to an interface'
    route '{%{resource}_id}/assign'
    http_method :post
    blocking true

    input do
      resource VpsAdmin::API::Resources::NetworkInterface, value_label: :name,
        required: true
      resource VpsAdmin::API::Resources::HostIpAddress, name: :route_via,
        value_label: :addr
    end

    output do
      use :all
    end

    authorize do |u|
      allow
    end

    def exec
      ip = ::IpAddress.find(params[:ip_address_id])
      netif = input[:network_interface]

      if current_user.role != :admin && ( \
           (ip.user_id && ip.user_id != current_user.id) \
           || (netif.vps.user_id != current_user.id)
         )
        error('access denied')
      end

      maintenance_check!(netif.vps)

      @chain, _ = netif.add_route(
        ip,
        via: input[:route_via],
        is_user: current_user.role != :admin,
      )
      ip

    rescue VpsAdmin::API::Exceptions::IpAddressInUse
      error('IP address is already in use')

    rescue VpsAdmin::API::Exceptions::IpAddressInvalidLocation
      error('IP address is from the wrong location')

    rescue VpsAdmin::API::Exceptions::IpAddressNotOwned
      error('Use an IP address you already own first')

    rescue VpsAdmin::API::Exceptions::IpAddressInvalid => e
      error(e.message)
    end

    def state_id
      @chain && @chain.id
    end
  end

  class AssignWithHostAddress < HaveAPI::Action
    desc 'Route the address to an interface'
    route '{%{resource}_id}/assign_with_host_address'
    http_method :post
    blocking true

    input do
      resource VpsAdmin::API::Resources::NetworkInterface, value_label: :name,
        required: true
      resource VpsAdmin::API::Resources::HostIpAddress, value_label: :addr,
        desc: 'Host address to assign to the interface, defaults to the first address'
    end

    output do
      use :all
    end

    authorize do |u|
      allow
    end

    def exec
      ip = ::IpAddress.find(params[:ip_address_id])
      netif = input[:network_interface]

      if current_user.role != :admin && ( \
           (ip.user_id && ip.user_id != current_user.id) \
           || (netif.vps.user_id != current_user.id)
         )
        error('access denied')
      end

      if input[:host_ip_address] && input[:host_ip_address].ip_address != ip
        error('invalid host IP address')
      end

      host_addr = input[:host_ip_address] || ip.host_ip_addresses.take!

      maintenance_check!(netif.vps)

      @chain, _ = netif.add_route(ip, host_addrs: [host_addr])
      ip

    rescue VpsAdmin::API::Exceptions::IpAddressInUse
      error('IP address is already in use')

    rescue VpsAdmin::API::Exceptions::IpAddressInvalidLocation
      error('IP address is from the wrong location')

    rescue VpsAdmin::API::Exceptions::IpAddressNotOwned
      error('Use an IP address you already own first')
    end

    def state_id
      @chain && @chain.id
    end
  end

  class Free < HaveAPI::Action
    desc 'Remove the route from an interface'
    route '{%{resource}_id}/free'
    http_method :post
    blocking true

    output do
      use :all
    end

    authorize do |u|
      allow
    end

    def exec
      ip = ::IpAddress.find(params[:ip_address_id])

      if current_user.role != :admin && ( \
           (ip.user_id && ip.user_id != current_user.id) \
           || (ip.network_interface_id && \
               ip.network_interface.vps.user_id != current_user.id) \
         )
        error('access denied')
      end

      netif = ip.network_interface

      maintenance_check!(netif.vps)

      @chain, _ = netif.remove_route(ip)
      ip

    rescue VpsAdmin::API::Exceptions::IpAddressInUse => e
      error(e.message)
    end

    def state_id
      @chain && @chain.id
    end
  end
end
