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
    string :addr, label: 'Address', desc: 'Address itself', db_name: :ip_addr
    integer :prefix, label: 'Prefix'
    integer :size, label: 'Size'
    use :shaper
  end

  params(:common) do
    use :filters, include: %i(network prefix size vps user addr)
    use :shaper
    integer :class_id, label: 'Class id', desc: 'Class id for shaper'
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
      input whitelist: %i(location network version role addr prefix vps limit offset)
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

      %i(prefix network vps user addr max_tx max_rx).each do |filter|
        next unless input.has_key?(filter)

        ips = ips.where(
          filter => input[filter],
        )
      end

      if input[:location]
        ips = ips.joins(:network).where(networks: {location_id: input[:location].id})
      end

      if input[:version]
        ips = ips.joins(:network).where(networks: {ip_version: input[:version]})
      end

      if input[:role]
        ips = ips.joins(:network).where(networks: {role: ::Network.roles[input[:role]]})
      end

      if current_user.role != :admin
        ips = ips.joins('LEFT JOIN vpses my_vps ON my_vps.id = ip_addresses.vps_id').where(
          'ip_addresses.user_id = ?
            OR (ip_addresses.vps_id IS NOT NULL AND my_vps.user_id = ?)
            OR (ip_addresses.user_id IS NULL AND ip_addresses.vps_id IS NULL)',
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
      end
    end

    def exec
      @ip
    end
  end

  class Create < HaveAPI::Actions::Default::Create
    desc 'Add an IP address'

    input do
      use :common, exclude: %i(vps class_id version location)
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
        if ip.vps && ip.network.location.environment.user_ip_ownership
          error('cannot chown IP while it belongs to a VPS')
        end

      elsif ip.network.role == 'interconnecting'
        error('interconnecting addresses cannot be modified')
      end

      @chain, _ = ip.do_update(input)
      ip

    rescue ActiveRecord::RecordInvalid => e
      error('update failed', e.record.errors.to_hash)
    end

    def state_id
      @chain.empty? ? nil : @chain.id
    end
  end
end
