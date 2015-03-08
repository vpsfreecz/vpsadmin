class VpsAdmin::API::Resources::User < HaveAPI::Resource
  version 1
  model ::User
  desc 'Manage users'

  params(:id) do
    id :id, label: 'User ID', db_name: :m_id
  end

  params(:common) do
    string :login, label: 'Login', db_name: :m_nick
    string :full_name, label: 'Full name', desc: 'First and last name',
           db_name: :m_name
    string :email, label: 'E-mail', db_name: :m_mail
    string :address, label: 'Address', db_name: :m_address
    integer :level, label: 'Access level', db_name: :m_level
    string :info, label: 'Info', db_name: :m_info
    integer :monthly_payment, label: 'Monthly payment', db_name: :m_monthly_payment,
            default: 300
    bool :mailer_enabled, label: 'Enabled mailer', db_name: :m_mailer_enable,
         default: true
    bool :playground_enabled, label: 'Enabled playground', db_name: :m_playground_enable,
         default: true
    string :state, label: 'State', desc: 'active, suspended or deleted', db_name: :m_state,
           default: 'active'
    string :suspend_reason, label: 'Suspend reason', db_name: :m_suspend_reason
  end

  params(:dates) do
    datetime :created_at, label: 'Created at', db_name: :m_created
    datetime :deleted_at, label: 'Deleted at', db_name: :m_deleted
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

    def exec
      ::User.all.limit(params[:user][:limit]).offset(params[:user][:offset])
    end
  end

  class Create < HaveAPI::Actions::Default::Create
    desc 'Create new user'

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
      user = ::User.new(to_db_names(input))
      user.create

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
      allow if u.role == :admin
      restrict m_id: u.id
      allow
    end

    def prepare
      @user = User.find_by(with_restricted)
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
      allow if u.role == :admin
    end

    def prepare
      @user = ::User.find(params[:user_id])
    end

    def exec
      @user
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
end
