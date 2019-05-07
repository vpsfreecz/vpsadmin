class UserSession < ActiveRecord::Base
  belongs_to :user, class_name: 'User', foreign_key: :user_id
  belongs_to :admin, class_name: 'User', foreign_key: :admin_id
  belongs_to :user_session_agent
  belongs_to :session_token
  has_many :transaction_chains

  def self.authenticate!(request, username, password, token: nil)
    user = ::User.login(request, username, password)

    if user.nil?
      self.current = nil
      ::User.current = nil
      return
    end

    self.current = create!(
      user: user,
      auth_type: token ? 'token' : 'basic',
      api_ip_addr: request.ip,
      api_ip_ptr: get_ptr(request.ip),
      client_ip_addr: request.env['HTTP_CLIENT_IP'],
      client_ip_ptr: request.env['HTTP_CLIENT_IP'] && get_ptr(request.env['HTTP_CLIENT_IP']),
      user_session_agent: ::UserSessionAgent.find_or_create!(request.user_agent || ''),
      client_version: request.user_agent || '',
      session_token_id: token && token.id,
      session_token_str: token && token.token
    )
  end

  def self.resume!(request, user, token: nil)
    begin
      self.current = find_session!(request, user, token: token)

    rescue ActiveRecord::RecordNotFound
      self.current = nil
      ::User.current = nil
      return
    end

    self.current.update!(last_request_at: Time.now)

    user.resume_login(request)
  end

  def self.close!(request, user, token: nil, session: nil)
    (session || find_session!(request, user, token: token)).update!(
      session_token: nil,
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
      session_token_id: token.id,
      closed_at: nil
    )
  end

  def self.get_ptr(ip)
    Resolv.new.getname(ip)

  rescue Resolv::ResolvError => e
    e.message
  end

  def self.current
    Thread.current[:user_session]
  end

  def self.current=(s)
    Thread.current[:user_session] = s
  end

  def start!(token)
    update!(
      session_token: token,
      session_token_str: token.token,
      auth_type: 'token'
    )
  end

  def user_agent
    user_session_agent.agent
  end
end
