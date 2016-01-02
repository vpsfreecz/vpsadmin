class VpsAdmin::API::Resources::AuthToken < HaveAPI::Resource
  model ::ApiToken
  desc 'Manage authentication tokens'

  params(:id) do
    id :id, label: 'Token ID'
  end

  params(:user) do
    resource VpsAdmin::API::Resources::User, label: 'User', desc: 'Token owner',
             value_label: :login
  end

  params(:label) do
    string :label, label: 'Label',
           desc: 'Label usually contains the client the token was created with'
  end

  params(:create) do
    use :label
    string :lifetime, label: 'Lifetime type',
           choices: %i(fixed renewable_manual renewable_auto permanent)
    integer :interval, label: 'Interval',
            desc: 'An interval of validity the token was created with'
  end

  params(:common) do
    use :user
    string :token, label: 'Token', desc: 'Authentication token'
    datetime :valid_to, label: 'Valid to', desc: 'End of token validity period'
    use :create
    integer :use_count, label: 'Use count',
            desc: 'How many times was the token used to authenticate the user'
    datetime :created_at
  end

  params(:all) do
    use :id
    use :common
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List authentication tokens'

    input do
      use :user
    end

    output(:object_list) do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict user: u
      allow
    end

    def exec
      tokens = ::ApiToken
      tokens = tokens.where(user: input[:user]) if current_user.role == :admin && input[:user]
      tokens.where(with_restricted)
    end
  end

  class Create < HaveAPI::Actions::Default::Create
    desc 'Create a new token'

    input do
      use :user
      patch :user, required: true
      use :create
      patch :label, required: true
      patch :lifetime, required: true
      patch :interval, required: true
    end

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
    end

    def exec
      t = ::ApiToken.custom(input)

      if t.save
        ::UserSession.create!(
            user: t.user,
            auth_type: 'token',
            ip_addr: request.ip,
            user_session_agent: ::UserSessionAgent.find_or_create!(request.user_agent),
            client_version: request.user_agent,
            api_token_id: t.id,
            api_token_str: t.token,
            admin_id: current_user.id
        )
        ok(t)
      else
        error('save failed', t.errors.to_hash)
      end

    rescue ActiveRecord::RecordInvalid
      error('failed to create a session')
    end
  end

  class Show < HaveAPI::Actions::Default::Show
    desc 'Get a token'

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict user: u
      allow
    end

    def exec
      ::ApiToken.find_by!(with_restricted(id: params[:auth_token_id]))
    end
  end

  class Update < HaveAPI::Actions::Default::Update
    desc 'Update a token'

    input do
      use :label
    end

    authorize do |u|
      allow if u.role == :admin
      restrict user: u
      allow
    end

    def exec
      t = ::ApiToken.find_by!(with_restricted(id: params[:auth_token_id]))

      if t.update(input)
        ok
      else
        error('update failed', t.errors.to_hash)
      end
    end
  end

  class Delete < HaveAPI::Actions::Default::Delete
    desc 'Delete a token'

    authorize do |u|
      allow if u.role == :admin
      restrict user: u
      allow
    end

    def exec
      t = ::ApiToken.find_by!(with_restricted(id: params[:auth_token_id]))
      ::UserSession.close!(request, t.user, token: t)
      ok
    end
  end
end
