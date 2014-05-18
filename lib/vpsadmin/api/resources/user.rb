class VpsAdmin::API::Resources::User < HaveAPI::Resource
  version 1
  model ::User
  desc 'Manage users'

  params(:common) do
    string :login, label: 'Login', db_name: :m_nick
    string :full_name, label: 'Full name', desc: 'First and last name',
           db_name: :m_name
    string :email, label: 'E-mail', db_name: :m_mail
    string :address, label: 'Address', db_name: :m_address
    integer :level, label: 'Access level', db_name: :m_level
    string :info, label: 'Info', db_name: :m_info
    integer :monthly_payment, label: 'Monthly payment', db_name: :m_monthly_payment
    bool :mailer_enabled, label: 'Enabled mailer', db_name: :m_mailer_enable
    bool :playground_enabled, label: 'Enabled playground', db_name: :m_playground_enable
    string :state, label: 'State', desc: 'active, suspended or deleted', db_name: :m_state
    string :suspend_reason, label: 'Suspend reason', db_name: :m_suspend_reason
  end

  params(:dates) do
    datetime :created_at, label: 'Created at', db_name: :m_created
    datetime :deleted_at, label: 'Deleted at', db_name: :m_deleted
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List users'

    output(:users) do
      list_of_objects
      use :common
      use :dates
    end

    authorize do |u|
      allow if u.role == :admin
    end

    def exec
      ret = []

      ::User.all.each do |u|
        ret << to_param_names(u.attributes, :output)
      end

      ret
    end
  end

  class Create < HaveAPI::Actions::Default::Create
    desc 'Create new user'

    input do
      use :common
    end

    output do
      id :id, label: 'User id'
    end

    authorize do |u|
      allow if u.role == :admin
    end

    def exec
      puts "------------_>\n\n"
      p params[:user]
      puts "<-----------\n\n"
      user = ::User.new(to_db_names(params[:user]))

      if user.save
        ok({id: user.id})
      else
        error('save failed', to_param_names(user.errors.to_hash, :input))
      end
    end
  end
end
