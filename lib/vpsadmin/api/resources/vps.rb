class VpsAdmin::API::Resources::VPS < HaveAPI::Resource
  model ::Vps
  desc 'Manage VPS'

  params(:id) do
    id :id, label: 'VPS id', db_name: :vps_id
  end

  params(:template) do
    resource VpsAdmin::API::Resources::OsTemplate, label: 'OS template'
  end

  params(:common) do
    resource VpsAdmin::API::Resources::User, label: 'User', desc: 'VPS owner',
             value_label: :login
    string :hostname, desc: 'VPS hostname', db_name: :vps_hostname
    bool :manage_hostname, label: 'Manage hostname',
          desc: 'Determines whether vpsAdmin sets VPS hostname or not'
    use :template
    string :info, label: 'Info', desc: 'VPS description', db_name: :vps_info
    resource VpsAdmin::API::Resources::DnsResolver, label: 'DNS resolver',
             desc: 'DNS resolver the VPS will use'
    resource VpsAdmin::API::Resources::Node, label: 'Node', desc: 'Node VPS will run on',
             value_label: :domain_name
    bool :onboot, label: 'On boot', desc: 'Start VPS on node boot?',
         db_name: :vps_onboot, default: true
    bool :onstartall, label: 'On start all',
         desc: 'Start VPS on start all action?', db_name: :vps_onstartall,
         default: true
    string :config, label: 'Config', desc: 'Custom configuration options',
           db_name: :vps_config, default: ''
  end

  params(:dataset) do
    resource VpsAdmin::API::Resources::Dataset, label: 'Dataset',
             desc: 'Dataset the VPS resides in', value_label: :name
  end

  params(:read_only) do
    datetime :created_at, label: 'Created at'
  end

  params(:status) do
    bool :is_running, label: 'Running'
    integer :uptime, label: 'Uptime'
    float :loadavg
    integer :process_count, label: 'Process count'
    float :cpu_user
    float :cpu_nice
    float :cpu_system
    float :cpu_idle
    float :cpu_iowait
    float :cpu_irq
    float :cpu_softirq
    float :loadavg
    integer :used_memory, label: 'Used memory', desc: 'in MB'
    integer :used_swap, label: 'Used swap', desc: 'in MB'
    integer :used_diskspace, label: 'Used disk space', desc: 'in MB'
  end

  params(:resources) do
    VpsAdmin::API::ClusterResources.to_params(::Vps, self, resources: %i(memory swap cpu))
  end

  params(:all) do
    use :id
    use :common
    use :dataset
    use :read_only
    use :resources
    use :status
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List VPS'

    input do
      resource VpsAdmin::API::Resources::User, label: 'User', desc: 'Filter by owner',
               value_label: :login
      resource VpsAdmin::API::Resources::Node, label: 'Node', desc: 'Filter by node',
          value_label: :domain_name
      resource VpsAdmin::API::Resources::Location, label: 'Location', desc: 'Filter by location'
      resource VpsAdmin::API::Resources::Environment, label: 'Environment', desc: 'Filter by environment'
      use :template
    end

    output(:object_list) do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict m_id: u.m_id
      input blacklist: %i(user)
      output whitelist: %i(id user hostname manage_hostname os_template dns_resolver
                          node dataset memory swap cpu backup_enabled maintenance_lock
                          maintenance_lock_reason object_state expiration_date
                          is_running process_count used_memory used_swap used_diskspace
                          uptime loadavg cpu_user cpu_nice cpu_system cpu_idle cpu_iowait
                          cpu_irq cpu_softirq)
      allow
    end

    example do
      request({})
      response({vpses: [
        {
            id: 150,
            user: {
                id: 1,
                name: 'somebody'
            },
            hostname: 'thehostname',
            os_template: {
                id: 1,
                label: 'Scientific Linux 6'
            },
            info: 'My very important VPS',
            dns_resolver: {
                id: 1,
            },
            node: {
                id: 1,
                name: 'node1'
            },
            onboot: true,
            onstartall: true,
            backup_enabled: true,
            vps_config: '',
        }
      ]})
    end

    def query
      q = if input[:object_state]
        Vps.unscoped.where(
            object_state: Vps.object_states[input[:object_state]]
        )

      else
        Vps.existing
      end

      q = with_includes(q).includes(dataset_in_pool: [:dataset_properties])

      q = q.where(with_restricted)
      q = q.where(m_id: input[:user].id) if input[:user]

      if input[:node]
        q = q.where(vps_server: input[:node].id)
      end

      if input[:location]
        q = q.joins(:node).where(servers: {server_location: input[:location].id})
      end

      if input[:environment]
        q = q.joins(:node).where(servers: {environment_id: input[:environment].id})
      end

      if input[:os_template]
        q = q.where(os_template: input[:os_template])
      end

      q
    end

    def count
      query.count
    end

    def exec
      with_includes(query).includes(
          :vps_status,
          dataset_in_pool: [:dataset]
      ).limit(params[:vps][:limit]).offset(params[:vps][:offset])
    end
  end

  class Create < HaveAPI::Actions::Default::Create
    desc 'Create VPS'

    input do
      resource VpsAdmin::API::Resources::Environment, label: 'Environment',
               desc: 'Environment in which to create the VPS, for non-admins'
      resource VpsAdmin::API::Resources::Location, label: 'Location',
               desc: 'Location in which to create the VPS, for non-admins'
      use :common, exclude: %i(manage_hostname)
      VpsAdmin::API::ClusterResources.to_params(::Vps, self)

      patch :hostname, required: true
    end

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      input whitelist: %i(environment location hostname os_template
                          dns_resolver cpu memory swap diskspace ipv4 ipv6)
      output whitelist: %i(id user hostname manage_hostname os_template dns_resolver
                          node dataset memory swap cpu backup_enabled maintenance_lock
                          maintenance_lock_reason object_state expiration_date
                          is_running process_count used_memory used_swap used_diskspace
                          uptime loadavg cpu_user cpu_nice cpu_system cpu_idle cpu_iowait
                          cpu_irq cpu_softirq)
      allow
    end

    example 'Create vps' do
      request({
        vps: {
          user: 1,
          hostname: 'my-vps',
          os_template: 1,
          info: '',
          dns_resolver: 1,
          node: 1,
          onboot: true,
          onstartall: true,
          backup_enabled: true,
          vps_config: ''
        }
      })
      response({
        vps: {
            id: 150
        }
      })
      comment <<END
Create VPS owned by user with ID 1, template ID 1 and DNS resolver ID 1. VPS
will be created on node ID 1. Action returns ID of newly created VPS.
END
    end

    def exec
      if current_user.role == :admin
        input[:user] ||= current_user

      else
        if input[:environment].nil? && input[:location].nil?
          error('provide either an environment, a location or both')
        end

        if input[:environment]
          node = ::Node.pick_by_env(input[:environment], input[:location])

        else
          node = ::Node.pick_by_location(input[:location])
        end

        input.delete(:location)
        input.delete(:environment)

        unless node
          error('no free node is available in selected environment/location')
        end

        env = node.environment

        if !current_user.env_config(env, :can_create_vps)
          error('insufficient permission to create a VPS in this environment')

        elsif current_user.vps_in_env(env) >= current_user.env_config(env, :max_vps_count)
          error('cannot create more VPSes in this environment')
        end

        input.update({
            user: current_user,
            node: node
        })
      end

      maintenance_check!(input[:node])

      vps = ::Vps.new(to_db_names(input))
      vps.set_cluster_resources(input)

      if vps.create
        ok(vps)

      else
        error('save failed', to_param_names(vps.errors.to_hash, :input))
      end
    end
  end

  class Show < HaveAPI::Actions::Default::Show
    desc 'Show VPS properties'

    output do
      use :all
    end

    # example do
    #   request({})
    #   response({})
    #   comment ''
    # end

    authorize do |u|
      allow if u.role == :admin
      restrict m_id: u.m_id
      output whitelist: %i(id user hostname manage_hostname os_template dns_resolver
                          node dataset memory swap cpu backup_enabled maintenance_lock
                          maintenance_lock_reason object_state expiration_date
                          is_running process_count used_memory used_swap used_diskspace
                          uptime loadavg cpu_user cpu_nice cpu_system cpu_idle cpu_iowait
                          cpu_irq cpu_softirq)
      allow
    end

    def prepare
      @vps = with_includes(::Vps.including_deleted).includes(
          dataset_in_pool: [:dataset_properties]
      ).find_by!(with_restricted(
          vps_id: params[:vps_id])
      )
    end

    def exec
      @vps
    end
  end

  class Update < HaveAPI::Actions::Default::Update
    desc 'Update VPS'

    input do
      use :common
      VpsAdmin::API::ClusterResources.to_params(::Vps, self, resources: %i(cpu memory swap))
      string :change_reason, label: 'Change reason',
             desc: 'If filled, it is send to VPS owner in an email'
      bool :admin_override, label: 'Admin override',
           desc: 'Make it possible to assign more resource than the user actually has'
      string :admin_lock_type, label: 'Admin lock type', choices: %i(no_lock absolute not_less not_more),
          desc: 'How is the admin lock enforced'
    end

    authorize do |u|
      allow if u.role == :admin
      restrict m_id: u.m_id
      input whitelist: %i(hostname manage_hostname os_template dns_resolver cpu
                          memory swap)
      allow
    end

    def exec
      vps = ::Vps.including_deleted.find_by!(with_restricted(vps_id: params[:vps_id]))
      maintenance_check!(vps)

      if input.empty?
        error('provide at least one attribute to update')
      end

      update_object_state!(vps) if change_object_state?

      if input[:user]
        resources = ::Vps.cluster_resources[:required] + ::Vps.cluster_resources[:optional]

        resources.each do |r|
          if input.has_key?(r)
            error('resources cannot be changed when changing VPS owner')
          end
        end
      end

      if input[:manage_hostname] === false && input[:hostname]
        input.delete(:hostname)

      elsif input[:manage_hostname] === true && \
            (input[:hostname].nil? || input[:hostname].empty?)
        error('update failed', hostname: ['must be present'])
      end

      vps.update(to_db_names(input))
      ok

    rescue ActiveRecord::RecordInvalid => e
      error('update failed', e.record == vps ? to_param_names(vps.errors.to_hash, :input) : e.record.errors.to_hash)
    end
  end

  class Delete < HaveAPI::Actions::Default::Delete
    desc 'Delete VPS'

    input do
      bool :lazy, label: 'Lazy delete', desc: 'Only mark VPS as deleted',
           default: true, fill: true
    end

    authorize do |u|
      allow if u.role == :admin
      restrict m_id: u.m_id
      input whitelist: []
      allow
    end

    def exec
      vps = ::Vps.including_deleted.find_by!(with_restricted(vps_id: params[:vps_id]))
      maintenance_check!(vps)
      
      if current_user.role == :admin
        state = input[:lazy] ? :soft_delete : :hard_delete

      else
        state = :soft_delete
      end

      vps.set_object_state(
          state,
          reason: 'Deletion requested'
      )
      ok
    end
  end

  class Start < HaveAPI::Action
    desc 'Start VPS'
    route ':%{resource}_id/start'
    http_method :post

    authorize do |u|
      allow if u.role == :admin
      restrict m_id: u.m_id
      allow
    end

    def exec
      vps = ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))
      maintenance_check!(vps)
      object_state_check!(vps, vps.user)

      vps.start
      ok
    end
  end

  class Restart < HaveAPI::Action
    desc 'Restart VPS'
    route ':%{resource}_id/restart'
    http_method :post

    authorize do |u|
      allow if u.role == :admin
      restrict m_id: u.m_id
      allow
    end

    def exec
      vps = ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))
      maintenance_check!(vps)
      object_state_check!(vps, vps.user)

      vps.restart
      ok
    end
  end

  class Stop < HaveAPI::Action
    desc 'Stop VPS'
    route ':%{resource}_id/stop'
    http_method :post

    authorize do |u|
      allow if u.role == :admin
      restrict m_id: u.m_id
      allow
    end

    def exec
      vps = ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))
      maintenance_check!(vps)
      object_state_check!(vps, vps.user)

      vps.stop
      ok
    end
  end

  class Passwd < HaveAPI::Action
    desc 'Set root password'
    route ':%{resource}_id/passwd'
    http_method :post

    input(:hash) do
      string :type, label: 'Type', choices: %w(secure simple), default: 'secure',
             fill: true
    end

    output(:hash) do
      string :password, label: 'Password', desc: 'Auto-generated password'
    end

    authorize do |u|
      allow if u.role == :admin
      restrict m_id: u.m_id
      allow
    end

    def exec
      vps = ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))
      maintenance_check!(vps)

      {password: vps.passwd(input[:type].to_sym)}
    end
  end

  class Reinstall < HaveAPI::Action
    desc 'Reinstall VPS'
    route ':%{resource}_id/reinstall'
    http_method :post

    input do
      use :template
    end

    authorize do |u|
      allow if u.role == :admin
      restrict m_id: u.m_id
      allow
    end

    def exec
      vps = ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))
      maintenance_check!(vps)

      tpl = input[:os_template] || vps.os_template

      error('selected os template is disabled') unless tpl.enabled?

      vps.reinstall(tpl)
      ok
    end
  end

  class Migrate < HaveAPI::Action
    desc 'Migrate VPS to another node'
    route ':%{resource}_id/migrate'
    http_method :post

    input do
      resource VpsAdmin::API::Resources::Node, label: 'Node',
        value_label: :domain_name,
               required: true
      bool :replace_ip_addresses, label: 'Replace IP addresses',
          desc: 'When migrating to another location, current IP addresses are replaced by addresses from the new location'
      bool :outage_window, default: true
      bool :send_mail, default: true
      string :reason
    end

    authorize do |u|
      allow if u.role == :admin
    end

    def exec
      vps = ::Vps.includes(dataset_in_pool: [:dataset]).find(params[:vps_id])

      if vps.node == input[:node]
        error('the VPS already is on this very node')

      elsif input[:node].server_type != 'node'
        error('target node is not a hypervisor')
      end

      vps.migrate(input[:node], input)
      ok
    end
  end

  class Clone < HaveAPI::Action
    desc 'Clone VPS'
    route ':%{resource}_id/clone'
    http_method :post

    input do
      resource VpsAdmin::API::Resources::Environment, desc: 'Clone to environment'
      resource VpsAdmin::API::Resources::Location, desc: 'Clone to location'
      resource VpsAdmin::API::Resources::Node, desc: 'Clone to node', value_label: :name
      resource VpsAdmin::API::Resources::User, desc: 'The owner of the cloned VPS', value_label: :login
      #resource VpsAdmin::API::Resources::VPS, desc: 'Clone into an existing VPS', value_label: :hostname
      bool :subdatasets, default: true, fill: true
      bool :dataset_plans, default: true, fill: true, label: 'Dataset plans'
      bool :configs, default: true, fill: true
      bool :resources, default: true, fill: true,
           desc: 'Clone resources such as memory and CPU'
      bool :features, default: true, fill: true
      string :hostname
      bool :stop, default: true, fill: true,
           desc: 'Do a consistent clone - original VPS is stopped before making a snapshot'
      bool :keep_snapshots, default: false, fill: true, label: 'Keep snapshots',
          desc: 'Keep snapshots created during the cloning process'
    end

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict m_id: u.id
      input blacklist: %i(node user configs)
      output whitelist: %i(id user hostname manage_hostname os_template dns_resolver
                          node dataset memory swap cpu backup_enabled maintenance_lock
                          maintenance_lock_reason object_state expiration_date
                          is_running process_count used_memory used_swap used_disk uptime
                          loadavg cpu_user cpu_nice cpu_system cpu_idle cpu_iowait cpu_irq
                          cpu_softirq)
      allow
    end

    def exec
      vps = ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))
      maintenance_check!(vps)

      if current_user.role == :admin
        input[:user] ||= current_user

      else
        input[:user] = current_user
      end

      error('cannot clone into itself') if input[:vps] == vps

      if input[:vps]
        node = input[:vps].node

        if current_user.role != :admin && vps.user != input[:vps].user
          error('insufficient permission to clone into this VPS')
        end

      elsif input[:node]
        node = input[:node]

      else
        if input[:environment].nil?
          error('specify environment with location, node or vps')
        end

        node = ::Node.pick_by_env(input[:environment], input[:location], vps.node)
      end

      error('no node available in this environment') unless node

      env = node.environment

      if current_user.role != :admin && !current_user.env_config(env, :can_create_vps)
        error('insufficient permission to create a VPS in this environment')

      elsif !input[:vps] && \
            current_user.role != :admin && \
            current_user.vps_in_env(env) >= current_user.env_config(env, :max_vps_count)
          error('cannot create more VPSes in this environment')
      end

      if input[:hostname].nil? || input[:hostname].strip.length == 0
        input[:hostname] = "#{vps.hostname}-#{vps.id}-clone"
      end

      vps.clone(node, input)

    rescue ActiveRecord::RecordInvalid => e
      error('clone failed', to_param_names(e.record.errors.to_hash))
    end
  end

  class SwapWith < HaveAPI::Action
    desc 'Swap VPS with another'
    route ':%{resource}_id/swap_with'
    http_method :post

    input do
      resource VpsAdmin::API::Resources::VPS, desc: 'Swap with this VPS',
          required: true
      bool :resources,
        desc: 'Swap resources (CPU, memory and swap, not disk space)'
      bool :configs, desc: 'Swap configuration chains'
      bool :hostname, desc: 'Swap hostname'
      bool :expirations, desc: 'Swap expirations'
    end

    authorize do |u|
      allow if u.role == :admin
      restrict m_id: u.id
      input blacklist: %i(configs expirations)
      allow
    end

    def exec
      vps = ::Vps.includes(:node).find_by!(
          with_restricted(vps_id: params[:vps_id])
      )
      maintenance_check!(vps)
      maintenance_check!(input[:vps])

      if vps.user != input[:vps].user
        error('access denied')

      elsif vps.node.server_location == input[:vps].node.server_location
        error("swap within one location is not supported")

      elsif vps.has_mount_of?(input[:vps]) || input[:vps].has_mount_of?(vps)
        error("swapping VPSes with mounts of each other is not supported")
      end

      if current_user.role != :admin
        input[:configs] = true
        input[:expirations] = true
      end

      vps.swap_with(input[:vps], input)
      ok
    end
  end

  include VpsAdmin::API::Maintainable::Action
  include VpsAdmin::API::Lifetimes::Resource
  add_lifetime_methods([Start, Stop, Restart])

  class Config < HaveAPI::Resource
    route ':vps_id/configs'
    desc 'Manage VPS configs'
    model ::VpsHasConfig

    params(:all) do
      resource VpsAdmin::API::Resources::VpsConfig, label: 'VPS config'
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List VPS configs'

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.m_id
        allow
      end

      def query
        @vps ||= ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))

        ::VpsHasConfig.where(vps: @vps)
      end

      def count
        query.count
      end

      def exec
        query.order('`order`').limit(input[:limit]).offset(input[:offset])
      end
    end

    class Replace < HaveAPI::Actions::Default::Update
      desc 'Replace VPS configs'
      route 'replace'
      http_method :post

      input(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        vps = ::Vps.find(params[:vps_id])
        maintenance_check!(vps)

        vps.applyconfig(input.map { |cfg| cfg[:vps_config].id })
      end
    end
  end

  class Feature < HaveAPI::Resource
    model ::VpsFeature
    route ':vps_id/features'
    desc 'Toggle VPS features'

    params(:toggle) do
      bool :enabled
    end

    params(:common) do
      string :name
      string :label
      use :toggle
    end

    params(:all) do
      id :id
      use :common
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List VPS features'

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.id
        allow
      end

      def query
        ::Vps.find_by!(with_restricted(vps_id: params[:vps_id])).vps_features
      end

      def count
        query.count
      end

      def exec
        query
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show VPS feature'
      resolve ->(f){ [f.vps_id, f.id] }

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.id
        allow
      end

      def prepare
        @feature = ::Vps.find_by!(
            with_restricted(vps_id: params[:vps_id])
        ).vps_features.find(params[:feature_id])
      end

      def exec
        @feature
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Toggle VPS feature'

      input do
        use :toggle
      end

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.id
        allow
      end

      def exec
        vps = ::Vps.find_by!(
            with_restricted(vps_id: params[:vps_id])
        )
        vps.set_feature(vps.vps_features.find(params[:feature_id]), input[:enabled])
      end
    end

    class UpdateAll < HaveAPI::Action
      desc 'Set all features at once'
      http_method :post
      route 'update_all'

      input do
        ::VpsFeature::FEATURES.each do |name, label|
          bool name, label: label
        end
      end

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.id
        allow
      end

      def exec
        vps = ::Vps.find_by!(
            with_restricted(vps_id: params[:vps_id])
        )
        vps.set_features(input)
      end
    end
  end

  class IpAddress < HaveAPI::Resource
    model ::IpAddress
    route ':vps_id/ip_addresses'
    desc 'Manage VPS IP addresses'

    params(:common) do
      id :id, label: 'IP address ID', db_name: :ip_id
      string :addr, label: 'Address', desc: 'Address itself', db_name: :ip_addr
      integer :version, label: 'IP version', desc: '4 or 6', db_name: :ip_v
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List VPS IP addresses'

      input do
        integer :version, label: 'IP version', desc: '4 or 6', db_name: :ip_v
      end

      output(:object_list) do
        use :common
      end

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.m_id
        allow
      end

      def exec
        ips = ::Vps.find_by!(
            with_restricted(vps_id: params[:vps_id])
        ).ip_addresses

        if input[:version]
          ips = ips.where(
              ip_v: input[:version]
          )
        end

        ips.limit(input[:limit]).offset(input[:offset])
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Assign IP address to VPS'

      input do
        resource VpsAdmin::API::Resources::IpAddress, label: 'IP address',
            desc: 'If the address is not provided, first free IP address of given version is assigned instead'
        integer :version, label: 'IP version',
                desc: 'provide only if IP address is not selected', db_name: :ip_v
      end

      output do
        use :common
      end

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.id
        allow
      end

      def exec
        vps = ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))
        maintenance_check!(vps)

        if input[:ip_address]
          begin
            vps.add_ip(ip = input[:ip_address])

          rescue VpsAdmin::API::Exceptions::IpAddressInUse
            error('IP address is already in use')

          rescue VpsAdmin::API::Exceptions::IpAddressInvalidLocation
            error('IP address is from the wrong location')

          rescue VpsAdmin::API::Exceptions::IpAddressNotOwned
            error('Use an IP address you already own first')
          end

        elsif input[:version].nil?
          error('provide either an IP address or IP version')

        else
          begin
            ip = vps.add_free_ip(input[:version])

          rescue ActiveRecord::RecordNotFound
            error('no free IP address is available')
          end
        end

        ok(ip)
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Free IP address'

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.id
        allow
      end

      def exec
        vps = ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))
        maintenance_check!(vps)

        vps.delete_ip(vps.ip_addresses.find_by!(
            ip_id: params[:ip_address_id],
            vps_id: vps.id)
        )
      end
    end

    class DeleteAll < HaveAPI::Action
      desc 'Free all IP addresses'
      route ''
      http_method :delete

      input(namespace: :ip_addresses) do
        integer :version, label: 'IP version',
                desc: '4 or 6, delete addresses of selected version', db_name: :ip_v
      end

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.id
        allow
      end

      def exec
        vps = ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))
        maintenance_check!(vps)

        vps.delete_ips((params[:ip_addresses] || {})[:version])
      end
    end
  end

  class Mount < HaveAPI::Resource
    route ':vps_id/mounts'
    model ::Mount
    desc 'Manage mounts'

    params(:all) do
      id :id
      resource VpsAdmin::API::Resources::VPS, value_label: :hostname
      resource VpsAdmin::API::Resources::Dataset, label: 'Dataset',
               value_label: :name
      resource VpsAdmin::API::Resources::Dataset::Snapshot, label: 'Snapshot',
               value_label: :created_at
      string :mountpoint, label: 'Mountpoint', db_name: :dst
      string :mode, label: 'Mode', choices: %w(ro rw), default: 'rw', fill: true
      string :on_start_fail, label: 'On mount failure',
             choices: ::Mount.on_start_fails.keys,
             desc: 'What happens when the mount fails during VPS start'
      datetime :expiration_date, label: 'Expiration date',
        desc: 'The mount is deleted when expiration date passes'
      bool :enabled, label: 'Enabled'
      bool :master_enabled, label: 'Master enabled'
      string :current_state, label: 'Current state',
             choices: ::Mount.current_states.keys
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List mounts'

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict vps: {m_id: u.id}
        allow
      end

      def query
        ::Mount.joins(:vps).where(with_restricted(vps_id: params[:vps_id]))
      end

      def count
        query.count
      end

      def exec
        query.limit(input[:limit]).offset(input[:offset])
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show mount'
      resolve ->(m){ [m.vps_id, m.id] }

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict vps: {m_id: u.id}
        allow
      end

      def prepare
        @mount = ::Mount.joins(:vps).find_by!(with_restricted(
                                                  vps_id: params[:vps_id],
                                                  id: params[:mount_id])
        )
      end

      def exec
        @mount
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Mount remote dataset or snapshot to directory in VPS'

      input do
        use :all, include: %i(dataset snapshot mountpoint mode on_start_fail)
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.id
        allow
      end

      def exec
        vps = ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))
        maintenance_check!(vps)

        if !input[:dataset] && !input[:snapshot]
          error('specify either a dataset or a snapshot')
        end

        if input[:dataset]
          ds = input[:dataset]

        else
          ds = input[:snapshot].dataset
        end

        if current_user.role != :admin && ds.user != current_user
          error('insufficient permission to mount selected snapshot')
        end

        if input[:dataset]
          vps.mount_dataset(input[:dataset], input[:mountpoint], input)

        else
          vps.mount_snapshot(input[:snapshot], input[:mountpoint], input)
        end

      rescue VpsAdmin::API::Exceptions::SnapshotAlreadyMounted => e
        error(e.message)

      rescue ActiveRecord::RecordInvalid => e
        error('create failed', e.record.errors.to_hash)
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update a mount'

      input do
        use :all, include: %i(on_start_fail enabled master_enabled)
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.id
        input blacklist: %i(master_enabled)
        allow
      end

      def exec
        vps = ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))
        maintenance_check!(vps)

        mnt = ::Mount.find_by!(vps: vps, id: params[:mount_id])
        mnt.update_chain(input)
        mnt
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete mount from VPS'

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.id
        allow
      end

      def exec
        vps = ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))
        maintenance_check!(vps)

        mnt = ::Mount.find_by!(vps: vps, id: params[:mount_id])
        vps.umount(mnt)

        ok
      end
    end
  end
  
  class OutageWindow < HaveAPI::Resource
    route ':vps_id/outage_windows'
    model ::VpsOutageWindow
    desc 'Manage VPS outage windows'
   
    params(:editable) do
      bool :is_open
      integer :opens_at
      integer :closes_at
    end

    params(:all) do
      integer :weekday
      use :editable
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List outage windows'

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.id
        allow
      end

      def query
        vps = ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))
        vps.vps_outage_windows
      end

      def count
        query.count
      end

      def exec
        query.order('weekday').offset(input[:offset]).limit(input[:limit])
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show outage window'
      resolve ->(w) { [w.vps_id, w.id] }

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.id
        allow
      end

      def prepare
        vps = ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))
        @window = vps.vps_outage_windows.find_by!(weekday: params[:outage_window_id])
      end
      
      def exec
        @window
      end
    end
    
    class Update < HaveAPI::Actions::Default::Update
      desc 'Resize outage window'

      input do
        use :editable
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.id
        allow
      end

      def exec
        vps = ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))
        maintenance_check!(vps)
        window = vps.vps_outage_windows.find_by!(weekday: params[:outage_window_id])

        if input.empty?
          error('provide parameters to change')
        end

        if input.has_key?(:is_open) && !input[:is_open]
          input[:opens_at] = nil
          input[:closes_at] = nil
        end

        window.update!(input)
        vps.log(:outage_window, {
            weekday: window.weekday,
            is_open: window.is_open,
            opens_at: window.opens_at,
            closes_at: window.closes_at,
        })
        window

      rescue ActiveRecord::RecordInvalid => e
        error('update failed', e.record.errors.to_hash)
      end
    end

    class UpdateAll < HaveAPI::Action
      desc 'Update outage windows for all week days at once'
      http_method :put
      route ''

      input do
        use :editable
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.id
        allow
      end

      def exec
        vps = ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))
        maintenance_check!(vps)

        if input.empty?
          error('provide parameters to change')
        end

        if input.has_key?(:is_open) && !input[:is_open]
          input[:opens_at] = nil
          input[:closes_at] = nil
        end

        ::Vps.transaction do
          data = []

          vps.vps_outage_windows.each do |w|
            w.update!(input)
            data << {
                weekday: w.weekday,
                is_open: w.is_open,
                opens_at: w.opens_at,
                closes_at: w.closes_at,
            }
          end
          
          vps.log(:outage_windows, data)
        end

        vps.vps_outage_windows.order('weekday')

      rescue ActiveRecord::RecordInvalid => e
        error('update failed', e.record.errors.to_hash)
      end
    end
  end

  class ConsoleToken < HaveAPI::Resource
    route ':vps_id/console_token'
    singular true
    model ::VpsConsole
    desc 'Remote console tokens'

    params(:all) do
      string :token, label: 'Token',
             desc: 'Authentication token'
      datetime :expiration, label: 'Expiration date',
          desc: 'A date after which the token becomes invalid'
    end

    class Create < HaveAPI::Actions::Default::Create
      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.id
        allow
      end

      def exec
        vps = ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))
        maintenance_check!(vps)

        t = ::VpsConsole.find_for(vps, current_user)

        if t
          t

        else
          ::VpsConsole.create_for!(vps, current_user)
        end

      rescue ::ActiveRecord::RecordInvalid => e
        error('failed to create a token', e.record.errors.to_hash)
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.id
        allow
      end

      def exec
        vps = ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))
        maintenance_check!(vps)

        ::VpsConsole.find_for!(vps, current_user)
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.id
        allow
      end

      def exec
        vps = ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))
        maintenance_check!(vps)

        ::VpsConsole.find_for!(vps, current_user).update!(token: nil)
      end
    end
  end

  class Status < HaveAPI::Resource
    desc 'View VPS statuses in time'
    route ':vps_id/statuses'
    model ::VpsStatus

    params(:all) do
      id :id
      bool :status
      bool :is_running, label: 'Running'
      integer :uptime, label: 'Uptime'
      float :loadavg
      integer :process_count, label: 'Process count'
      integer :cpus
      float :cpu_user
      float :cpu_nice
      float :cpu_system
      float :cpu_idle
      float :cpu_iowait
      float :cpu_irq
      float :cpu_softirq
      float :loadavg
      integer :total_memory
      integer :used_memory, label: 'Used memory', desc: 'in MB'
      integer :total_swap
      integer :used_swap, label: 'Used swap', desc: 'in MB'
      datetime :created_at
    end
  
    class Index < HaveAPI::Actions::Default::Index
      input do
        datetime :from
        datetime :to
        bool :status
        bool :is_running

        patch :limit, fill: true
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.id
        allow
      end

      def query
        vps = ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))
        q = vps.vps_statuses
        q = q.where('created_at >= ?', input[:from]) if input[:from]
        q = q.where('created_at <= ?', input[:to]) if input[:to]
        q = q.where(status: input[:status]) if input[:status]
        q = q.where(is_running: input[:is_running]) if input[:is_running]
        q
      end

      def count
        query.count
      end

      def exec
        query.order('created_at DESC').offset(input[:offset]).limit(input[:limit])
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      output do
        use :all
      end
      
      authorize do |u|
        allow if u.role == :admin
        restrict m_id: u.id
        allow
      end

      def exec
        vps = ::Vps.find_by!(with_restricted(vps_id: params[:vps_id]))
        vps.vps_statuses.find(params[:status_id])
      end
    end
  end
end
