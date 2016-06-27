class VpsAdmin::API::Resources::IpAddress < HaveAPI::Resource
  model ::IpAddress
  desc 'Manage IP addresses'

  params(:id) do
    id :id, label: 'ID', desc: 'IP address ID', db_name: :ip_id
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
    resource VpsAdmin::API::Resources::Network, label: 'Network'
    resource VpsAdmin::API::Resources::Location, label: 'Location',
              desc: 'Location this IP address is available in'
    resource VpsAdmin::API::Resources::User, label: 'User',
             value_label: :login
    string :role, choices: ::Network.roles.keys
    use :shaper
  end

  params(:common) do
    use :filters, include: %i(network vps user)
    use :shaper
    string :addr, label: 'Address', desc: 'Address itself', db_name: :ip_addr
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
      input whitelist: %i(location version role limit offset)
      output blacklist: %i(class_id)
      allow
    end

    example do
      request({
        ip_addresses: {
          vps_id: 101
        }
      })
      response({
        ip_addresses: [
            {
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
            }
        ]
      })
      comment 'List IP addresses assigned to VPS with ID 101.'
    end

    def query
      ips = ::IpAddress

      %i(network vps user max_tx max_rx).each do |filter|
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
        ips = ips.where(
            'user_id = ? OR user_id IS NULL', current_user.id
        ).where(vps_id: nil).order('user_id DESC, ip_id ASC')
      end

      ips
    end

    def count
      query.count
    end

    def exec
      with_includes(query).order('ip_id').limit(input[:limit]).offset(input[:offset])
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
        ).where(ip_id: params[:ip_address_id]).take!
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

      ::IpAddress.register(addr, input) # model

    rescue ArgumentError => e
      error(e.message, {addr: ['not a valid IP address']})

    rescue ::ActiveRecord::RecordInvalid => e
      error('create failed', e.record.errors.to_hash)
    end
  end

  class Update < HaveAPI::Actions::Default::Update
    desc 'Update IP address'

    input do
      use :shaper
    end

    authorize do |u|
      allow if u.role == :admin
    end

    def exec
      ip = ::IpAddress.find(params[:ip_address_id])
      ip.set_shaper(input[:max_tx], input[:max_rx])
    end
  end
end
