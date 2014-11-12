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
      user = ::User.new(to_db_names(params[:user]))

      if user.save
        ok(user)
      else
        error('save failed', to_param_names(user.errors.to_hash, :input))
      end
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
end
