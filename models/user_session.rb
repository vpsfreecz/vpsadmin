class UserSession < ActiveRecord::Base
  belongs_to :user, class_name: 'User', foreign_key: :user_id
  belongs_to :admin, class_name: 'User', foreign_key: :admin_id
  belongs_to :user_session_agent
  belongs_to :api_token
  has_many :transaction_chains

  def self.authenticate!(request, username, password, token: nil)
    user = ::User.login(request, username, password)
    return unless user

    self.current = create!(
        user: user,
        auth_type: token ? 'token' : 'basic',
        ip_addr: request.ip,
        user_session_agent: ::UserSessionAgent.find_or_create!(request.user_agent),
        client_version: request.user_agent,
        api_token_id: token && token.id,
        api_token_str: token && token.token
    )
  end

  def self.resume!(request, user, token: nil)
    begin
      self.current = find_session!(request, user, token: token)

    rescue ActiveRecord::RecordNotFound
      return
    end

    self.current.update!(last_request_at: Time.now)
    
    user.resume_login(request)
  end

  def self.close!(request, user, token: nil, session: nil)
    (session || find_session!(request, user, token: token)).update!(
        api_token: nil,
        closed_at: Time.now
    )
    token && token.destroy!
  end

  def self.one_time!(request, username, password)
    s = authenticate!(request, username, password)

    if s
      close!(request, s.user, session: s)
      s.user
    end
  end

  def self.find_session!(request, user, token: nil)
    find_by!(
        user: user,
        api_token_id: token.id,
        closed_at: nil
    )
  end

  def self.current
    Thread.current[:user_session]
  end
  
  def self.current=(s)
    Thread.current[:user_session] = s
  end
  
  def start!(token)
    update!(
        api_token: token,
        api_token_str: token.token,
        auth_type: 'token'
    )
  end
end
