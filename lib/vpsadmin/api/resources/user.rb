class VpsAdmin::API::Resources::User < HaveAPI::Resource
  version 1
  model ::User
  desc 'Manage users'

  params(:id) do
    id :id, label: 'User ID', db_name: :m_id
  end

  params(:writable) do
    string :login, label: 'Login', db_name: :m_nick
    string :full_name, label: 'Full name', desc: 'First and last name',
           db_name: :m_name
    string :email, label: 'E-mail', db_name: :m_mail
    string :address, label: 'Address', db_name: :m_address
    integer :level, label: 'Access level', db_name: :m_level
    string :info, label: 'Info', db_name: :m_info
    integer :monthly_payment, label: 'Monthly payment', db_name: :m_monthly_payment,
            default: 300
    datetime :paid_until, label: 'Paid until'
    bool :mailer_enabled, label: 'Enabled mailer', db_name: :m_mailer_enable,
         default: true
    bool :playground_enabled, label: 'Enabled playground', db_name: :m_playground_enable,
         default: true
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
    datetime :last_activity, label: 'Last activity'
  end

  params(:dates) do
    datetime :created_at, label: 'Created at', db_name: :m_created
  end

  params(:all) do
    use :id
    use :common
    use :dates
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List users'

    output(:object_list) do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
    end

    def query
      if input[:object_state]
        ::User.unscoped.where(
            object_state: ::User.object_states[input[:object_state]]
        )

      else
        ::User.existing.all
      end
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
      vps_params = %i(vps node environment location os_template)

      passwd = input.delete(:password)
      user = ::User.new(to_db_names(input.select { |k,_| !vps_params.include?(k) }))
      user.set_password(passwd) if passwd

      if input[:vps]
        if input[:os_template].nil?
          error('provide an OS template')
        end

        if input[:environment].nil? && input[:location].nil? && input[:node].nil?
          error('provide either an environment, a location or a node')
        end

        if input[:node]
          node = input[:node]

        elsif input[:environment]
          node = ::Node.pick_by_env(input[:environment], input[:location])

        else
          node = ::Node.pick_by_location(input[:location])
        end

        unless node
          error('no free node is available in selected environment/location')
        end

        input[:node] = node
      end

      user.create(input[:vps], input[:node], input[:os_template])

    rescue ActiveRecord::RecordInvalid
      error('create failed', to_param_names(user.errors.to_hash, :input))
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
    route ':user_id/touch'

    authorize do |u|
      allow
    end

    def prepare
      if current_user.role != :admin && current_user.id != params[:user_id].to_i
        error('access denied')
      end

      @user = User.find(params[:user_id])
    end

    def exec
      @user.m_last_activity = Time.new.to_i
      @user.save
    end
  end

  class Show < HaveAPI::Actions::Default::Show
    output do
      use :all
    end

    authorize do |u|
      allow
    end

    def prepare
      if current_user.role != :admin && current_user.id != params[:user_id].to_i
        error('access denied')
      end

      @user = ::User.find(params[:user_id])
    end

    def exec
      @user
    end
  end

  class Update < HaveAPI::Actions::Default::Update
    input do
      use :writable
      use :password
    end

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      input whitelist: %i(password mailer_enabled)
      allow
    end

    def exec
      if current_user.role != :admin && current_user.id != params[:user_id].to_i
        error('access denied')
      end

      u = ::User.including_deleted.find_by!(m_id: params[:user_id])

      if input.empty?
        error('provide at least one attribute to update')
      end

      update_object_state!(u) if change_object_state?

      if input[:paid_until]
        u.m_paid_until = input.delete(:paid_until).to_i.to_s
      end

      if input[:password]
        error('update failed',
              password: ['password must be at least 8 characters long']
        ) if input[:password].length < 8

        u.set_password(input.delete(:password))
      end

      u.update!(to_db_names(input))
      u
    end
  end

  class Delete < HaveAPI::Actions::Default::Delete
    authorize do |u|
      allow if u.role == :admin
    end

    def exec
      u = ::User.including_deleted.find(params[:user_id])
      update_object_state!(u)
    end
  end

  class ClusterResource < HaveAPI::Resource
    desc "Manage user's cluster resources"
    version 1
    model ::UserClusterResource
    route ':user_id/cluster_resources'

    params(:common) do
      resource VpsAdmin::API::Resources::Environment
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

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow
      end

      def query
        if current_user.role != :admin && current_user.id != params[:user_id].to_i
          error("I don't like the smell of this")
        end

        ::UserClusterResource.where(user_id: params[:user_id])
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

      output do
        use :all
      end

      authorize do |u|
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
            user: ::User.find(params[:user_id]),
        }))

      rescue ActiveRecord::RecordInvalid => e
        error('create failed', e.record.errors.to_hash)
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update a cluster resource'

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
        ::UserClusterResource.find_by!(
            user_id: params[:user_id],
            id: params[:cluster_resource_id]
        ).update!(input)

      rescue ActiveRecord::RecordInvalid => e
        error('update failed', e.record.errors.to_hash)
      end
    end
  end

  include VpsAdmin::API::Lifetimes::Resource
  add_lifetime_params(Current, :output, :lifetime_expiration)
end
