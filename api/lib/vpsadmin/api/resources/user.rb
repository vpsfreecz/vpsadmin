class VpsAdmin::API::Resources::User < HaveAPI::Resource
  model ::User
  desc VpsAdmin::API::I18n.message('resources.user.description')

  params(:id) do
    id :id, label: 'User ID'
  end

  params(:writable) do
    string :login, label: 'Login'
    string :full_name, label: 'Full name', desc: 'First and last name'
    string :email, label: 'E-mail'
    string :address, label: 'Address'
    string :time_zone, label: 'Time zone', nullable: true,
                       desc: 'IANA time zone identifier, e.g. Europe/Prague'
    integer :level, label: 'Access level'
    string :info, label: 'Info'
    bool :mailer_enabled, label: 'Enabled mailer', default: true
    bool :password_reset, label: 'Password reset'
    bool :lockout, label: 'Lock-out'
    resource VpsAdmin::API::Resources::Language, label: 'Language of e-mails'
    bool :enable_basic_auth, label: 'Enable HTTP basic authentication'
    bool :enable_token_auth, label: 'Enable token authentication'
    bool :enable_oauth2_auth, label: 'Enable OAuth2 authentication'
    bool :enable_single_sign_on, label: 'Enable single sign-on'
    bool :enable_new_login_notification, label: 'Enable new login notification'
    bool :enable_multi_factor_auth, label: 'Enable multi-factor authentication'
    integer :preferred_session_length, label: 'Preferred session length'
    bool :preferred_logout_all, label: 'Preferred logout all'
  end

  params(:password) do
    string :password, label: 'Password',
                      desc: 'The password must be at least 8 characters long'
  end

  params(:vps) do
    bool :vps, label: 'Create a VPS'
    resource VpsAdmin::API::Resources::Node, label: 'Node', desc: 'Node VPS will run on',
                                             value_label: :name
    resource VpsAdmin::API::Resources::Environment, label: 'Environment',
                                                    desc: 'Environment in which to create the VPS'
    resource VpsAdmin::API::Resources::Location, label: 'Location',
                                                 desc: 'Location in which to create the VPS'
    resource VpsAdmin::API::Resources::OsTemplate, label: 'OS template'
  end

  params(:common) do
    use :writable
    datetime :last_activity_at, label: 'Last activity'
    string :dokuwiki_groups, label: 'DokuWiki groups',
                             desc: 'Comma-separated list of DokuWiki groups'
  end

  params(:dates) do
    datetime :created_at, label: 'Created at'
  end

  params(:all) do
    use :id
    use :common
    use :dates
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List users'

    input do
      use :writable
      bool :admin, desc: 'Filter users with administrator privileges'
    end

    output(:object_list) do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict id: u.id
      input whitelist: %i[from_id limit]
      allow
    end

    def query
      q = if input[:object_state]
            ::User.unscoped.where(with_restricted(
                                    object_state: ::User.object_states[input[:object_state]]
                                  ))

          else
            ::User.existing.where(with_restricted)
          end

      in_params = self.class.input

      %i[login full_name email address info].each do |p|
        next unless input[p]

        q = q.where("#{in_params[p].db_name} LIKE ? COLLATE utf8_unicode_ci", input[p].to_s)
      end

      %i[level mailer_enabled].each do |p|
        next unless input[p]

        q = q.where(in_params[p].db_name => input[p])
      end

      q = q.where('level >= 90') if input[:admin]

      q
    end

    def count
      query.count
    end

    def exec
      with_pagination(query)
    end
  end

  class Create < HaveAPI::Actions::Default::Create
    desc 'Create new user'
    blocking true

    input do
      use :writable
      use :password
      use :vps
    end

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
    end

    def exec
      vps_params = %i[vps node environment location os_template]

      passwd = input.delete(:password)
      user = ::User.new(to_db_names(input.except(*vps_params)))
      user.set_password(passwd) if passwd

      if input[:vps]
        error!('provide an OS template') if input[:os_template].nil?

        if input[:node]
          node = input[:node]

        elsif input[:location] || input[:environment]
          environment = input[:environment] || input[:location]&.environment
          required_diskspace =
            VpsAdmin::API::Operations::Utils::PoolSpace.required_default_new_vps_diskspace!(
              environment:,
              os_template: input[:os_template]
            )

          node = VpsAdmin::API::Operations::Node::Pick.run(
            environment: input[:environment],
            location: input[:location],
            required_diskspace:
          )

        else
          error!('provide either an environment, a location or a node')
        end

        error!('no free node is available in selected environment/location') unless node

        input[:node] = node
      end

      @chain, = TransactionChains::User::Create.fire(
        user,
        input[:vps],
        input[:node],
        input[:os_template]
      )
      user
    rescue ActiveRecord::RecordInvalid
      error!('create failed', to_param_names(user.errors.to_hash, :input))
    rescue VpsAdmin::API::Exceptions::OperationError => e
      error!(e.message)
    end

    def state_id
      @chain && @chain.id
    end
  end

  class Current < HaveAPI::Action
    desc 'Get user that is authenticated during this request'

    output do
      use :all
    end

    authorize do
      allow
    end

    def prepare
      current_user
    end

    def exec
      current_user
    end
  end

  class Touch < HaveAPI::Action
    desc VpsAdmin::API::I18n.message('resources.user.actions.touch.description')
    route '{user_id}/touch'

    authorize do |u|
      allow if u
    end

    def prepare
      error!(VpsAdmin::API::I18n.message('errors.access_denied_lower')) if current_user.role != :admin && current_user.id != path_params['user_id'].to_i

      @user = User.find(path_params['user_id'])
    end

    def exec
      @user.last_activity_at = Time.now
      @user.save
    end
  end

  class Show < HaveAPI::Actions::Default::Show
    output do
      use :all
    end

    authorize do |u|
      allow if u
    end

    def prepare
      error!(VpsAdmin::API::I18n.message('errors.access_denied_lower')) if current_user.role != :admin && current_user.id != path_params['user_id'].to_i

      @user = ::User.find(path_params['user_id'])
    end

    def exec
      @user
    end
  end

  class AvailableIps < HaveAPI::Action
    desc 'Get number of user-owned free IP addresses that can be used in a given location'
    route '{user_id}/available_ips'

    input do
      resource VpsAdmin::API::Resources::Location, label: 'Location', required: true,
                                                   desc: 'Location where the VPS will run'
      resource VpsAdmin::API::Resources::Location, name: :address_location,
                                                   label: 'Address location',
                                                   desc: 'Location to select IP addresses from'
    end

    output(:hash) do
      integer :ipv4, label: 'IPv4'
      integer :ipv4_private, label: 'Private IPv4'
      integer :ipv6, label: 'IPv6'
    end

    authorize do
      allow
    end

    def exec
      error!(VpsAdmin::API::I18n.message('errors.access_denied_lower')) if current_user.role != :admin && current_user.id != path_params['user_id'].to_i

      @user = ::User.find(path_params['user_id'])
      @location = input[:location]
      @address_location = input[:address_location]

      if @address_location && !@location.shares_any_networks_with_primary?(
        @address_location,
        userpick: current_user.role == :admin ? nil : true
      )
        error!("no shared networks with location #{@address_location.label}")
      end

      {
        ipv4: count_addrs(ip_v: 4, role: :public_access),
        ipv4_private: count_addrs(ip_v: 4, role: :private_access),
        ipv6: count_addrs(ip_v: 6, role: :public_access)
      }
    end

    protected

    def count_addrs(ip_v:, role:)
      q = ::IpAddress
          .joins(network: :location_networks)
          .joins("LEFT JOIN resource_locks rl ON rl.resource = 'IpAddress' AND rl.row_id = ip_addresses.id")
          .where(
            ip_addresses: { user_id: @user.id },
            networks: {
              ip_version: ip_v,
              role: ::Network.roles[role],
              purpose: [::Network.purposes[:any], ::Network.purposes[:vps]]
            }
          )
          .where('ip_addresses.network_interface_id IS NULL')
          .where('rl.id IS NULL')

      q = if @address_location
            shared_networks = @location.any_shared_networks_with_primary(
              @address_location,
              userpick: current_user.role == :admin ? nil : true
            )

            if current_user.role == :admin
              q.where(networks: { id: shared_networks.map(&:id) })
            else
              q.where(
                networks: { id: shared_networks.map(&:id) },
                location_networks: { userpick: true }
              )
            end
          else
            q.where(location_networks: { location_id: @location.id, autopick: true })
          end

      q.distinct.count(:id)
    end
  end

  class Update < HaveAPI::Actions::Default::Update
    blocking true

    input do
      use :writable
      string :password, label: 'Current password', protected: true,
                        desc: 'The password must be at least 8 characters long'
      string :new_password, label: 'Password', protected: true,
                            desc: 'The password must be at least 8 characters long'
      bool :logout_sessions, label: 'Logout sessions',
                             desc: 'Logout all sessions except the current one when password is changed',
                             default: true
    end

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      input whitelist: %i[
        password new_password logout_sessions language
        time_zone
        enable_basic_auth enable_token_auth enable_oauth2_auth enable_single_sign_on
        enable_new_login_notification enable_multi_factor_auth
        preferred_session_length preferred_logout_all remind_after_date
      ]
      allow
    end

    def exec
      error!(VpsAdmin::API::I18n.message('errors.access_denied_lower')) if current_user.role != :admin && current_user.id != path_params['user_id'].to_i

      u = ::User.including_deleted.find(path_params['user_id'])

      error!('provide at least one attribute to update') if input.empty?

      update_object_state!(u) if change_object_state?
      object_state_check!(u)

      if input.has_key?(:new_password)
        if current_user.role != :admin && !input.has_key?(:password)
          error!(
            'update failed',
            password: ['current password must be entered']
          )
        end

        if input[:new_password].nil? || input[:new_password].length < 8
          error!(
            'update failed',
            new_password: ['password must be at least 8 characters long']
          )
        end

        if current_user.role != :admin
          auth = VpsAdmin::API::Operations::Authentication::Password.run(
            u.login,
            input[:password],
            multi_factor: false
          )

          if auth.nil? || !auth.authenticated?
            error!(
              'update failed',
              password: ['incorrect password']
            )
          end
        end

        u.set_password(input.delete(:new_password))

        if input.fetch(:logout_sessions, true)
          VpsAdmin::API::Operations::UserSession::CloseAll.run(
            u,
            except: current_user == u ? [::UserSession.current] : nil
          )
        end
      end

      input.delete(:password)
      input.delete(:logout_sessions)

      u.update!(to_db_names(input))
      u
    rescue ActiveRecord::RecordInvalid => e
      error!('update failed', to_param_names(e.record.errors.to_hash, :input))
    end

    def state_id
      @chain && @chain.id
    end
  end

  class Delete < HaveAPI::Actions::Default::Delete
    blocking true

    authorize do |u|
      allow if u.role == :admin
    end

    def exec
      u = ::User.including_deleted.find(path_params['user_id'])
      update_object_state!(u)
    end

    def state_id
      @chain.id
    end
  end

  class NotificationDeliveryMethod < HaveAPI::Resource
    desc 'Manage user event delivery methods'
    route '{user_id}/notification_delivery_methods'
    model ::UserNotificationDeliveryMethod

    params(:all) do
      string :id, db_name: :delivery_method
      string :delivery_method,
             choices: { values: ::VpsAdmin::API::Notifications::Actions.labels },
             load_validators: false
      string :label
      bool :enabled
      datetime :created_at, nullable: true
      datetime :updated_at, nullable: true
    end

    def self.find_method(user_id, delivery_method)
      user = ::User.find(user_id)
      method = ::UserNotificationDeliveryMethod.normalize_delivery_method(delivery_method)
      raise ActiveRecord::RecordNotFound unless ::UserNotificationDeliveryMethod.known_delivery_method?(method)

      user.user_notification_delivery_methods.find_by(delivery_method: method) ||
        ::UserNotificationDeliveryMethod.new(
          user:,
          delivery_method: method,
          enabled: ::UserNotificationDeliveryMethod.default_enabled?(method)
        )
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List user event delivery methods'

      output(:object_list) do
        use :all
      end

      authorize do |_u|
        allow
      end

      def query
        error!('Access denied') if current_user.role != :admin && current_user.id != path_params['user_id'].to_i

        ::UserNotificationDeliveryMethod.all_methods_for(::User.find(path_params['user_id']))
      end

      def count
        query.count
      end

      def exec
        query
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show user event delivery method'

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      def exec
        error!('Access denied') if current_user.role != :admin && current_user.id != path_params['user_id'].to_i

        self.class.resource.find_method(
          path_params['user_id'],
          path_params['notification_delivery_method_id']
        )
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update user event delivery method'

      input do
        bool :enabled, required: true
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        user = ::User.find(path_params['user_id'])

        user.set_notification_delivery_method!(
          path_params['notification_delivery_method_id'],
          input[:enabled]
        )
      rescue ArgumentError => e
        error!(e.message)
      rescue ActiveRecord::RecordInvalid => e
        error!('update failed', e.record.errors.to_hash)
      end
    end
  end

  class EnvironmentConfig < HaveAPI::Resource
    desc 'User settings per environment'
    model ::EnvironmentUserConfig
    route '{user_id}/environment_configs'

    params(:all) do
      id :id, label: 'ID'
      use :common
    end

    params(:common) do
      resource VpsAdmin::API::Resources::Environment
      bool :can_create_vps, label: 'Can create a VPS', default: false
      bool :can_destroy_vps, label: 'Can destroy a VPS', default: false
      integer :vps_lifetime, label: 'Default VPS lifetime',
                             desc: 'in seconds, 0 is unlimited', default: 0
      integer :max_vps_count, label: 'Maximum number of VPS per user',
                              desc: '0 is unlimited', default: 1
      bool :default, label: 'Default',
                     desc: 'If true, the user config is inherited from the environment config',
                     default: true
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List settings per environment'

      input do
        use :common, include: %i[environment]
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        output blacklist: %i[default]
        allow
      end

      def query
        error!(VpsAdmin::API::I18n.message('errors.access_denied_lower')) if current_user.role != :admin && path_params['user_id'].to_i != current_user.id

        q = ::EnvironmentUserConfig.where(user_id: path_params['user_id'])

        q = q.where(environment: input[:environment]) if input[:environment]

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
      desc 'Show settings in an environment'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        output blacklist: %i[default]
        allow
      end

      def prepare
        error!(VpsAdmin::API::I18n.message('errors.access_denied_lower')) if current_user.role != :admin && path_params['user_id'].to_i != current_user.id

        @cfg = ::EnvironmentUserConfig.where(
          user_id: path_params['user_id'],
          id: path_params['environment_config_id']
        ).take!
      end

      def exec
        @cfg
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Change settings in an environment'

      input do
        use :common, exclude: %i[environment]
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        error!('provide at least one parameter to update') if input.empty?

        cfg = ::EnvironmentUserConfig.find_by!(
          user_id: path_params['user_id'],
          id: path_params['environment_config_id']
        )

        VpsAdmin::API::Operations::Environment::UpdateUserConfig.run(cfg, input)
      rescue ActiveRecord::RecordInvalid => e
        error!('update failed', e.record.errors.to_hash)
      end
    end
  end

  class ClusterResource < HaveAPI::Resource
    desc "Manage user's cluster resources"
    model ::UserClusterResource
    route '{user_id}/cluster_resources'

    params(:filters) do
      resource VpsAdmin::API::Resources::Environment
    end

    params(:common) do
      use :filters
      resource VpsAdmin::API::Resources::ClusterResource
      integer :value
    end

    params(:status) do
      integer :used, label: 'Used', desc: 'Number of used resource units'
      integer :free, label: 'Free', desc: 'Number of free resource units '
    end

    params(:all) do
      id :id
      use :common
      use :status
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List user cluster resources'

      input do
        use :filters
      end

      output(:object_list) do
        use :all
      end

      authorize do |_u|
        allow
      end

      def query
        if current_user.role != :admin && current_user.id != path_params['user_id'].to_i
          error!("I don't like the smell of this")
        end

        q = ::UserClusterResource.where(user_id: path_params['user_id'])
        q = q.where(environment: input[:environment]) if input[:environment]
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
      desc 'Show user cluster resource'
      resolve ->(ucr) { [ucr.user_id, ucr.id] }

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      def prepare
        @r = with_includes.find_by!(
          user_id: path_params['user_id'],
          id: path_params['cluster_resource_id']
        )
      end

      def exec
        if current_user.role != :admin && current_user.id != path_params['user_id'].to_i
          error!("I don't like the smell of this")
        end

        @r
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create a cluster resource for user'

      input do
        use :common
        patch :environment, required: true
        patch :cluster_resource, required: true
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        ::UserClusterResource.create!(input.update({
                                                     user: ::User.find(path_params['user_id'])
                                                   }))
      rescue ActiveRecord::RecordInvalid => e
        error!('create failed', e.record.errors.to_hash)
      end
    end
  end

  class KnownDevice < HaveAPI::Resource
    desc 'Manage known login devices'
    route '{user_id}/known_devices'
    model ::UserDevice

    params(:all) do
      id :id
      string :api_ip_addr, label: 'IP Address'
      string :api_ip_ptr, label: 'IP PTR'
      string :client_ip_addr, label: 'Client IP Address'
      string :client_ip_ptr, label: 'Client IP PTR'
      string :user_agent, label: 'User agent', db_name: :user_agent_string
      datetime :skip_multi_factor_auth_until
      datetime :created_at
      datetime :updated_at
      datetime :last_seen_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List known devices'

      output(:object_list) do
        use :all
      end

      authorize do |_u|
        allow
      end

      def query
        error!(VpsAdmin::API::I18n.message('errors.access_denied_lower')) if current_user.role != :admin && current_user.id != path_params['user_id'].to_i

        self.class.model.active.where(user_id: path_params['user_id'])
      end

      def count
        query.count
      end

      def exec
        with_pagination(query)
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show known device'
      resolve ->(device) { [device.user_id, device.id] }

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      def prepare
        error!(VpsAdmin::API::I18n.message('errors.access_denied_lower')) if current_user.role != :admin && current_user.id != path_params['user_id'].to_i

        @device = self.class.model.active.find_by!(
          user_id: path_params['user_id'],
          id: path_params['known_device_id']
        )
      end

      def exec
        @device
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      include VpsAdmin::API::Lifetimes::ActionHelpers

      desc 'Delete known device'

      authorize do |_u|
        allow
      end

      def exec
        error!(VpsAdmin::API::I18n.message('errors.access_denied_lower')) if current_user.role != :admin && current_user.id != path_params['user_id'].to_i

        device = self.class.model.active.find_by!(
          user_id: path_params['user_id'],
          id: path_params['known_device_id']
        )
        object_state_check!(device.user)

        device.close
        ok!
      rescue VpsAdmin::API::Exceptions::OperationError => e
        error!(e.message)
      end
    end
  end

  class TotpDevice < HaveAPI::Resource
    desc 'Manage TOTP devices'
    route '{user_id}/totp_devices'
    model ::UserTotpDevice

    params(:all) do
      id :id
      string :label
      bool :confirmed
      bool :enabled
      datetime :last_use_at
      integer :use_count
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List configured TOTP devices'

      input do
        use :all, include: %i[confirmed enabled]
      end

      output(:object_list) do
        use :all
      end

      authorize do |_u|
        allow
      end

      def query
        error!(VpsAdmin::API::I18n.message('errors.access_denied_lower')) if current_user.role != :admin && current_user.id != path_params['user_id'].to_i

        q = ::UserTotpDevice.where(user_id: path_params['user_id'])

        %i[confirmed enabled].each do |v|
          q = q.where(v => input[v]) if input.has_key?(v)
        end

        q
      end

      def count
        query.count
      end

      def exec
        with_pagination(query)
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show configured TOTP device'
      resolve ->(device) { [device.user_id, device.id] }

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      def prepare
        error!(VpsAdmin::API::I18n.message('errors.access_denied_lower')) if current_user.role != :admin && current_user.id != path_params['user_id'].to_i

        @device = ::UserTotpDevice.find_by!(
          user_id: path_params['user_id'],
          id: path_params['totp_device_id']
        )
      end

      def exec
        @device
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      include VpsAdmin::API::Lifetimes::ActionHelpers

      desc 'Create a new TOTP device'

      input do
        string :label, required: true
      end

      output do
        use :all
        string :secret
        string :provisioning_uri
      end

      authorize do |_u|
        allow
      end

      def exec
        error!(VpsAdmin::API::I18n.message('errors.access_denied_lower')) if current_user.role != :admin && current_user.id != path_params['user_id'].to_i

        u = ::User.find(path_params['user_id'])
        object_state_check!(u)

        VpsAdmin::API::Operations::TotpDevice::Create.run(u, input[:label])
      rescue VpsAdmin::API::Exceptions::OperationError => e
        error!(e.message)
      end
    end

    class Confirm < HaveAPI::Action
      include VpsAdmin::API::Lifetimes::ActionHelpers

      desc 'Confirm device'
      route '{totp_device_id}/confirm'
      http_method :post

      input(:hash) do
        string :code, label: 'TOTP code', required: true
      end

      output(:hash) do
        string :recovery_code
      end

      authorize do |_u|
        allow
      end

      def exec
        error!(VpsAdmin::API::I18n.message('errors.access_denied_lower')) if current_user.role != :admin && current_user.id != path_params['user_id'].to_i

        device = ::UserTotpDevice.find_by!(
          user_id: path_params['user_id'],
          id: path_params['totp_device_id']
        )
        object_state_check!(device.user)

        recovery_code = VpsAdmin::API::Operations::TotpDevice::Confirm.run(
          device,
          input[:code]
        )

        { recovery_code: }
      rescue VpsAdmin::API::Exceptions::OperationError => e
        error!(e.message)
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      include VpsAdmin::API::Lifetimes::ActionHelpers

      desc 'Update device label'

      input do
        string :label
        bool :enabled
      end

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      def exec
        if current_user.role != :admin && current_user.id != path_params['user_id'].to_i
          error!(VpsAdmin::API::I18n.message('errors.access_denied_lower'))
        elsif input.empty?
          error!('nothing to do')
        end

        device = ::UserTotpDevice.find_by!(
          user_id: path_params['user_id'],
          id: path_params['totp_device_id']
        )
        object_state_check!(device.user)

        if input[:label]
          VpsAdmin::API::Operations::TotpDevice::Update.run(
            device,
            label: input[:label]
          )
        end

        if input.has_key?(:enabled)
          op =
            if input[:enabled]
              VpsAdmin::API::Operations::TotpDevice::Enable
            else
              VpsAdmin::API::Operations::TotpDevice::Disable
            end

          op.run(device)
        end

        device
      rescue VpsAdmin::API::Exceptions::OperationError => e
        error!(e.message)
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      include VpsAdmin::API::Lifetimes::ActionHelpers

      desc 'Delete TOTP device'

      authorize do |_u|
        allow
      end

      def exec
        error!(VpsAdmin::API::I18n.message('errors.access_denied_lower')) if current_user.role != :admin && current_user.id != path_params['user_id'].to_i

        device = ::UserTotpDevice.find_by!(
          user_id: path_params['user_id'],
          id: path_params['totp_device_id']
        )
        object_state_check!(device.user)

        VpsAdmin::API::Operations::TotpDevice::Delete.run(device)
        ok!
      rescue VpsAdmin::API::Exceptions::OperationError => e
        error!(e.message)
      end
    end
  end

  class WebauthnCredential < HaveAPI::Resource
    desc 'Manage WebAuthn credentials'
    route '{user_id}/webauthn_credentials'
    model ::WebauthnCredential

    params(:all) do
      id :id
      string :label
      bool :enabled
      integer :use_count
      datetime :last_use_at
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List configured WebAuthn credentials'

      input do
        use :all, include: %i[enabled]
      end

      output(:object_list) do
        use :all
      end

      authorize do |_u|
        allow
      end

      def query
        error!(VpsAdmin::API::I18n.message('errors.access_denied_lower')) if current_user.role != :admin && current_user.id != path_params['user_id'].to_i

        q = self.class.model.where(user_id: path_params['user_id'])
        q = q.where(enabled: input[:enabled]) if input.has_key?(:enabled)
        q
      end

      def count
        query.count
      end

      def exec
        with_pagination(query)
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show WebAuthn credential'
      resolve ->(cred) { [cred.user_id, cred.id] }

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      def prepare
        error!(VpsAdmin::API::I18n.message('errors.access_denied_lower')) if current_user.role != :admin && current_user.id != path_params['user_id'].to_i

        @cred = self.class.model.find_by!(
          user_id: path_params['user_id'],
          id: path_params['webauthn_credential_id']
        )
      end

      def exec
        @cred
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      include VpsAdmin::API::Lifetimes::ActionHelpers

      desc 'Update WebAuthn credential'

      input do
        use :all, include: %i[label enabled]
      end

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      def exec
        if current_user.role != :admin && current_user.id != path_params['user_id'].to_i
          error!(VpsAdmin::API::I18n.message('errors.access_denied_lower'))
        elsif input.empty?
          error!('nothing to do')
        end

        cred = self.class.model.find_by!(
          user_id: path_params['user_id'],
          id: path_params['webauthn_credential_id']
        )
        object_state_check!(cred.user)

        cred.update!(input)
        cred
      rescue ActiveRecord::RecordInvalid => e
        error!('update failed', e.record.errors.to_hash)
      rescue VpsAdmin::API::Exceptions::OperationError => e
        error!(e.message)
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      include VpsAdmin::API::Lifetimes::ActionHelpers

      desc 'Delete WebAuthn credential'

      authorize do |_u|
        allow
      end

      def exec
        error!(VpsAdmin::API::I18n.message('errors.access_denied_lower')) if current_user.role != :admin && current_user.id != path_params['user_id'].to_i

        cred = self.class.model.find_by!(
          user_id: path_params['user_id'],
          id: path_params['webauthn_credential_id']
        )
        object_state_check!(cred.user)

        cred.destroy!

        ok!
      rescue VpsAdmin::API::Exceptions::OperationError => e
        error!(e.message)
      end
    end
  end

  class PublicKey < HaveAPI::Resource
    desc 'Manage public keys'
    route '{user_id}/public_keys'
    model ::UserPublicKey

    params(:common) do
      string :label, label: 'Label'
      text :key, label: 'Public key'
      bool :auto_add, label: 'Auto add',
                      desc: 'Add this key automatically into newly created VPS'
    end

    params(:readonly) do
      string :fingerprint, label: 'Fingerprint', desc: 'MD5 fingerprint'
      string :comment, label: 'Comment'
    end

    params(:all) do
      id :id
      use :common
      use :readonly
      datetime :created_at, label: 'Created at'
      datetime :updated_at, label: 'Updated at'
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List saved public keys'

      output(:object_list) do
        use :all
      end

      authorize do |_u|
        allow
      end

      def query
        error!(VpsAdmin::API::I18n.message('errors.access_denied')) if current_user.role != :admin && current_user.id != path_params['user_id'].to_i

        ::UserPublicKey.where(user_id: path_params['user_id'])
      end

      def count
        query.count
      end

      def exec
        with_pagination(query)
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show saved public key'

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      def prepare
        error!(VpsAdmin::API::I18n.message('errors.access_denied')) if current_user.role != :admin && current_user.id != path_params['user_id'].to_i

        @key = ::UserPublicKey.find_by!(user_id: path_params['user_id'], id: path_params['public_key_id'])
      end

      def exec
        @key
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      include VpsAdmin::API::Lifetimes::ActionHelpers

      desc 'Store a public key'

      input do
        use :common
        patch :label, required: true
        patch :key, required: true
        patch :auto_add, default: false, fill: true
      end

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      def exec
        error!(VpsAdmin::API::I18n.message('errors.access_denied')) if current_user.role != :admin && current_user.id != path_params['user_id'].to_i

        user = ::User.find(path_params['user_id'])
        object_state_check!(user)

        input[:user] = user
        input[:key].strip!

        ::UserPublicKey.create!(input)
      rescue ActiveRecord::RecordInvalid => e
        error!('create failed', e.record.errors.to_hash)
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      include VpsAdmin::API::Lifetimes::ActionHelpers

      desc 'Update a public key'

      input do
        use :common
      end

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      def exec
        error!(VpsAdmin::API::I18n.message('errors.access_denied')) if current_user.role != :admin && current_user.id != path_params['user_id'].to_i

        error!('Provide at least one input parameter') if input.empty?

        key = ::UserPublicKey.find_by!(user_id: path_params['user_id'], id: path_params['public_key_id'])
        object_state_check!(key.user)

        input[:key].strip! if input[:key]

        key.update!(input)
        key
      rescue ActiveRecord::RecordInvalid => e
        error!('update failed', e.record.errors.to_hash)
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      include VpsAdmin::API::Lifetimes::ActionHelpers

      desc 'Delete public key'

      authorize do |_u|
        allow
      end

      def exec
        error!(VpsAdmin::API::I18n.message('errors.access_denied')) if current_user.role != :admin && current_user.id != path_params['user_id'].to_i

        key = ::UserPublicKey.find_by!(user_id: path_params['user_id'], id: path_params['public_key_id'])
        object_state_check!(key.user)

        key.destroy!
        ok!
      end
    end
  end

  class EmailRoleRecipient < HaveAPI::Resource
    desc 'Manage user email recipients'
    route '{user_id}/email_role_recipients'
    model ::UserEmailRoleRecipient

    params(:all) do
      string :id, db_name: :role
      string :label
      string :description
      string :to
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List user email role recipients'

      output(:object_list) do
        use :all
      end

      authorize do |_u|
        allow
      end

      def query
        error!(VpsAdmin::API::I18n.message('errors.access_denied')) if current_user.role != :admin && current_user.id != path_params['user_id'].to_i

        ::UserEmailRoleRecipient.all_roles_for(::User.find(path_params['user_id']))
      end

      def count
        query.count
      end

      def exec
        query
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show user email role recipient'

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      def prepare
        error!(VpsAdmin::API::I18n.message('errors.access_denied')) if current_user.role != :admin && current_user.id != path_params['user_id'].to_i

        unless ::UserEmailRoleRecipient.registered_role?(path_params['email_role_recipient_id'])
          raise ActiveRecord::RecordNotFound
        end

        @recp = ::UserEmailRoleRecipient.find_by!(
          user_id: path_params['user_id'],
          role: path_params['email_role_recipient_id']
        )
      end

      def exec
        @recp
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      include VpsAdmin::API::Lifetimes::ActionHelpers

      desc 'Update user email role recipient'

      input do
        use :all, include: %i[to]
      end

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      def exec
        error!(VpsAdmin::API::I18n.message('errors.access_denied')) if current_user.role != :admin && current_user.id != path_params['user_id'].to_i
        user = ::User.find(path_params['user_id'])
        object_state_check!(user)

        ::UserEmailRoleRecipient.handle_update!(
          user,
          path_params['email_role_recipient_id'],
          input
        )
      rescue ActiveRecord::RecordInvalid => e
        error!('Update failed', e.record.errors.to_hash)
      end
    end
  end

  class NotificationTemplateRecipient < HaveAPI::Resource
    desc 'Manage user email recipients'
    route '{user_id}/notification_template_recipients'
    model ::UserNotificationTemplateRecipient

    def self.user_visible_template!(name)
      tpl = ::NotificationTemplate.find_by!(name:)

      if tpl.user_visibility == 'visible' || (tpl.user_visibility == 'default' && tpl.desc[:public])
        return tpl
      end

      raise ActiveRecord::RecordNotFound
    end

    params(:all) do
      string :id, db_name: :name
      string :label
      string :description
      string :to
      bool :enabled
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List user notification template recipients'

      output(:object_list) do
        use :all
      end

      authorize do |_u|
        allow
      end

      def query
        error!(VpsAdmin::API::I18n.message('errors.access_denied')) if current_user.role != :admin && current_user.id != path_params['user_id'].to_i

        ::UserNotificationTemplateRecipient.all_templates_for(::User.find(path_params['user_id']))
      end

      def count
        query.count
      end

      def exec
        query
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show user notification template recipient'

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      def prepare
        error!(VpsAdmin::API::I18n.message('errors.access_denied')) if current_user.role != :admin && current_user.id != path_params['user_id'].to_i

        tpl =
          if current_user.role == :admin
            ::NotificationTemplate.find_by!(name: path_params['notification_template_recipient_id'])
          else
            self.class.resource.user_visible_template!(path_params['notification_template_recipient_id'])
          end

        @recp = ::UserNotificationTemplateRecipient.find_by!(
          user_id: path_params['user_id'],
          notification_template: tpl
        )
      end

      def exec
        @recp
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      include VpsAdmin::API::Lifetimes::ActionHelpers

      desc 'Update user notification template recipient'

      input do
        use :all, include: %i[to enabled]
      end

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      def exec
        error!(VpsAdmin::API::I18n.message('errors.access_denied')) if current_user.role != :admin && current_user.id != path_params['user_id'].to_i
        user = ::User.find(path_params['user_id'])
        object_state_check!(user)
        tpl =
          if current_user.role == :admin
            ::NotificationTemplate.find_by!(name: path_params['notification_template_recipient_id'])
          else
            self.class.resource.user_visible_template!(path_params['notification_template_recipient_id'])
          end

        ::UserNotificationTemplateRecipient.handle_update!(
          user,
          tpl,
          input
        )
      rescue ActiveRecord::RecordInvalid => e
        error!('Update failed', e.record.errors.to_hash)
      end
    end
  end

  include VpsAdmin::API::Lifetimes::Resource

  add_lifetime_methods([Update])
  add_lifetime_params(Current, :output, :lifetime_expiration)
end
