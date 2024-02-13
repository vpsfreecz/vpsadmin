class VpsAdmin::API::Resources::User < HaveAPI::Resource
  model ::User
  desc 'Manage users'

  params(:id) do
    id :id, label: 'User ID'
  end

  params(:writable) do
    string :login, label: 'Login'
    string :full_name, label: 'Full name', desc: 'First and last name'
    string :email, label: 'E-mail'
    string :address, label: 'Address'
    integer :level, label: 'Access level'
    string :info, label: 'Info'
    bool :mailer_enabled, label: 'Enabled mailer', default: true
    bool :password_reset, label: 'Password reset'
    bool :lockout, label: 'Lock-out'
    resource VpsAdmin::API::Resources::Language, label: 'Language of e-mails'
    bool :enable_single_sign_on, label: 'Enable single sign-on'
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
    end

    def query
      q = if input[:object_state]
            ::User.unscoped.where(
              object_state: ::User.object_states[input[:object_state]]
            )

          else
            ::User.existing.all
          end

      in_params = self.class.input

      %i[login full_name email address info].each do |p|
        next unless input[p]

        q = q.where("#{in_params[p].db_name} LIKE ? COLLATE utf8_unicode_ci", "#{input[p]}")
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
      query.limit(params[:user][:limit]).offset(params[:user][:offset])
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
      user = ::User.new(to_db_names(input.select { |k, _| !vps_params.include?(k) }))
      user.set_password(passwd) if passwd

      if input[:vps]
        error('provide an OS template') if input[:os_template].nil?

        if input[:node]
          node = input[:node]

        elsif input[:location] || input[:environment]
          node = VpsAdmin::API::Operations::Node::Pick.run(
            environment: input[:environment],
            location: input[:location]
          )

        else
          error('provide either an environment, a location or a node')
        end

        error('no free node is available in selected environment/location') unless node

        input[:node] = node
      end

      @chain, = user.create(input[:vps], input[:node], input[:os_template])
      user
    rescue ActiveRecord::RecordInvalid
      error('create failed', to_param_names(user.errors.to_hash, :input))
    end

    def state_id
      @chain.empty? ? nil : @chain.id
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
    desc 'Update last activity'
    route '{user_id}/touch'

    authorize do |_u|
      allow
    end

    def prepare
      error('access denied') if current_user.role != :admin && current_user.id != params[:user_id].to_i

      @user = User.find(params[:user_id])
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

    authorize do |_u|
      allow
    end

    def prepare
      error('access denied') if current_user.role != :admin && current_user.id != params[:user_id].to_i

      @user = ::User.find(params[:user_id])
    end

    def exec
      @user
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
    end

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      input whitelist: %i[
        password new_password mailer_enabled language enable_single_sign_on
        preferred_session_length preferred_logout_all remind_after_date
      ]
      allow
    end

    def exec
      error('access denied') if current_user.role != :admin && current_user.id != params[:user_id].to_i

      u = ::User.including_deleted.find(params[:user_id])

      error('provide at least one attribute to update') if input.empty?

      update_object_state!(u) if change_object_state?

      if input.has_key?(:new_password)
        if current_user.role != :admin && !input.has_key?(:password)
          error(
            'update failed',
            password: ['current password must be entered']
          )
        end

        if input[:new_password].nil? || input[:new_password].length < 8
          error(
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
            error(
              'update failed',
              password: ['incorrect password']
            )
          end
        end

        u.set_password(input.delete(:new_password))
      end

      input.delete(:password)

      u.update!(to_db_names(input))
      u
    rescue ActiveRecord::RecordInvalid => e
      error('update failed', to_param_names(e.record.errors.to_hash, :input))
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
      u = ::User.including_deleted.find(params[:user_id])
      update_object_state!(u)
    end

    def state_id
      @chain.id
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
        error('access denied') if current_user.role != :admin && params[:user_id].to_i != current_user.id

        q = ::EnvironmentUserConfig.where(user_id: params[:user_id])

        q = q.where(environment: input[:environment]) if input[:environment]

        q
      end

      def count
        query.count
      end

      def exec
        with_includes(query).limit(input[:limit]).offset(input[:offset])
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
        error('access denied') if current_user.role != :admin && params[:user_id].to_i != current_user.id

        @cfg = ::EnvironmentUserConfig.where(
          user_id: params[:user_id],
          id: params[:environment_config_id]
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

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        error('provide at least one parameter to update') if input.empty?

        ::EnvironmentUserConfig.find_by!(
          user_id: params[:user_id],
          id: params[:environment_config_id]
        ).update!(input)
      rescue ActiveRecord::RecordInvalid => e
        error('update failed', e.record.errors.to_hash)
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
        if current_user.role != :admin && current_user.id != params[:user_id].to_i
          error("I don't like the smell of this")
        end

        q = ::UserClusterResource.where(user_id: params[:user_id])
        q = q.where(environment: input[:environment]) if input[:environment]
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
          user_id: params[:user_id],
          id: params[:cluster_resource_id]
        )
      end

      def exec
        if current_user.role != :admin && current_user.id != params[:user_id].to_i
          error("I don't like the smell of this")
        end

        @r
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create a cluster resource for user'

      input do
        use :common
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        ::UserClusterResource.create!(input.update({
                                                     user: ::User.find(params[:user_id])
                                                   }))
      rescue ActiveRecord::RecordInvalid => e
        error('create failed', e.record.errors.to_hash)
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
        error('access denied') if current_user.role != :admin && current_user.id != params[:user_id].to_i

        q = ::UserTotpDevice.where(user_id: params[:user_id])

        %i[confirmed enabled].each do |v|
          q = q.where(v => input[v]) if input.has_key?(v)
        end

        q
      end

      def count
        query.count
      end

      def exec
        query.limit(input[:limit]).offset(input[:offset])
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
        error('access denied') if current_user.role != :admin && current_user.id != params[:user_id].to_i

        @device = ::UserTotpDevice.find_by!(
          user_id: params[:user_id],
          id: params[:totp_device_id]
        )
      end

      def exec
        @device
      end
    end

    class Create < HaveAPI::Actions::Default::Create
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
        error('access denied') if current_user.role != :admin && current_user.id != params[:user_id].to_i

        u = ::User.find(params[:user_id])
        VpsAdmin::API::Operations::TotpDevice::Create.run(u, input[:label])
      rescue VpsAdmin::API::Exceptions::OperationError => e
        error(e.message)
      end
    end

    class Confirm < HaveAPI::Action
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
        error('access denied') if current_user.role != :admin && current_user.id != params[:user_id].to_i

        device = ::UserTotpDevice.find_by!(
          user_id: params[:user_id],
          id: params[:totp_device_id]
        )

        recovery_code = VpsAdmin::API::Operations::TotpDevice::Confirm.run(
          device,
          input[:code]
        )

        { recovery_code: recovery_code }
      rescue VpsAdmin::API::Exceptions::OperationError => e
        error(e.message)
      end
    end

    class Update < HaveAPI::Actions::Default::Update
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
        if current_user.role != :admin && current_user.id != params[:user_id].to_i
          error('access denied')
        elsif input.empty?
          error('nothing to do')
        end

        device = ::UserTotpDevice.find_by!(
          user_id: params[:user_id],
          id: params[:totp_device_id]
        )

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
        error(e.message)
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete TOTP device'

      authorize do |_u|
        allow
      end

      def exec
        error('access denied') if current_user.role != :admin && current_user.id != params[:user_id].to_i

        device = ::UserTotpDevice.find_by!(
          user_id: params[:user_id],
          id: params[:totp_device_id]
        )

        VpsAdmin::API::Operations::TotpDevice::Delete.run(device)
        ok
      rescue VpsAdmin::API::Exceptions::OperationError => e
        error(e.message)
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
        error('Access denied') if current_user.role != :admin && current_user.id != params[:user_id].to_i

        ::UserPublicKey.where(user_id: params[:user_id])
      end

      def count
        query.count
      end

      def exec
        query.limit(input[:limit]).offset(input[:offset])
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
        error('Access denied') if current_user.role != :admin && current_user.id != params[:user_id].to_i

        @key = ::UserPublicKey.find_by!(user_id: params[:user_id], id: params[:public_key_id])
      end

      def exec
        @key
      end
    end

    class Create < HaveAPI::Actions::Default::Create
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
        error('Access denied') if current_user.role != :admin && current_user.id != params[:user_id].to_i

        input[:user] = ::User.find(params[:user_id])
        input[:key].strip!

        ::UserPublicKey.create!(input)
      rescue ActiveRecord::RecordInvalid => e
        error('create failed', e.record.errors.to_hash)
      end
    end

    class Update < HaveAPI::Actions::Default::Update
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
        error('Access denied') if current_user.role != :admin && current_user.id != params[:user_id].to_i

        error('Provide at least one input parameter') if input.empty?

        key = ::UserPublicKey.find_by!(user_id: params[:user_id], id: params[:public_key_id])

        input[:key].strip! if input[:key]

        key.update!(input)
        key
      rescue ActiveRecord::RecordInvalid => e
        error('update failed', e.record.errors.to_hash)
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete public key'

      authorize do |_u|
        allow
      end

      def exec
        error('Access denied') if current_user.role != :admin && current_user.id != params[:user_id].to_i

        key = ::UserPublicKey.find_by!(user_id: params[:user_id], id: params[:public_key_id])
        key.destroy!
        ok
      end
    end
  end

  class MailRoleRecipient < HaveAPI::Resource
    desc 'Manage user mail recipients'
    route '{user_id}/mail_role_recipients'
    model ::UserMailRoleRecipient

    params(:all) do
      string :id, db_name: :role
      string :label
      string :description
      string :to
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List user mail role recipients'

      output(:object_list) do
        use :all
      end

      authorize do |_u|
        allow
      end

      def query
        error('Access denied') if current_user.role != :admin && current_user.id != params[:user_id].to_i

        ::UserMailRoleRecipient.all_roles_for(::User.find(params[:user_id]))
      end

      def count
        query.count
      end

      def exec
        query
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show user mail role recipient'

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      def prepare
        error('Access denied') if current_user.role != :admin && current_user.id != params[:user_id].to_i

        @recp = ::UserMailRoleRecipient.find_by!(
          user_id: params[:user_id],
          role: params[:mail_role_recipient_id]
        )
      end

      def exec
        @recp
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update user mail role recipient'

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
        error('Access denied') if current_user.role != :admin && current_user.id != params[:user_id].to_i

        ::UserMailRoleRecipient.handle_update!(
          ::User.find(params[:user_id]),
          params[:mail_role_recipient_id],
          input
        )
      rescue ActiveRecord::RecordInvalid => e
        error('Update failed', e.record.errors.to_hash)
      end
    end
  end

  class MailTemplateRecipient < HaveAPI::Resource
    desc 'Manage user mail recipients'
    route '{user_id}/mail_template_recipients'
    model ::UserMailTemplateRecipient

    params(:all) do
      string :id, db_name: :name
      string :label
      string :description
      string :to
      bool :enabled
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List user mail template recipients'

      output(:object_list) do
        use :all
      end

      authorize do |_u|
        allow
      end

      def query
        error('Access denied') if current_user.role != :admin && current_user.id != params[:user_id].to_i

        ::UserMailTemplateRecipient.all_templates_for(::User.find(params[:user_id]))
      end

      def count
        query.count
      end

      def exec
        query
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show user mail template recipient'

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      def prepare
        error('Access denied') if current_user.role != :admin && current_user.id != params[:user_id].to_i

        @recp = ::UserMailTemplateRecipient.find_by!(
          user_id: params[:user_id],
          mail_template_id: params[:mail_template_id]
        )
      end

      def exec
        @recp
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update user mail template recipient'

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
        error('Access denied') if current_user.role != :admin && current_user.id != params[:user_id].to_i

        ::UserMailTemplateRecipient.handle_update!(
          ::User.find(params[:user_id]),
          ::MailTemplate.find_by!(name: params[:mail_template_recipient_id]),
          input
        )
      rescue ActiveRecord::RecordInvalid => e
        error('Update failed', e.record.errors.to_hash)
      end
    end
  end

  include VpsAdmin::API::Lifetimes::Resource
  add_lifetime_params(Current, :output, :lifetime_expiration)
end
