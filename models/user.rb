class User < ActiveRecord::Base
  self.table_name = 'members'
  self.primary_key = 'm_id'

  has_many :vpses, :foreign_key => :m_id
  has_many :transactions, foreign_key: :t_m_id
  has_many :storage_exports, foreign_key: :member_id
  has_many :environment_user_configs
  has_many :environments, through: :environment_user_configs

  before_validation :set_no_password

  alias_attribute :login, :m_nick
  alias_attribute :role, :m_level

  has_paper_trail ignore: [
      :m_last_activity,
  ]

  validates :m_level, :m_nick, :m_pass, presence: true
  validates :m_level, numericality: {
      only_integer: true
  }
  validates :m_nick, format: {
      with: /[a-zA-Z\.\-]{3,63}/,
      message: 'not a valid login'
  }, uniqueness: true
  validates :m_state, inclusion: {
      in: %w(active suspended deleted),
      message: '%{value} is not a valid user state'
  }

  default_scope { where.not(m_state: 'deleted') }

  include HaveAPI::Hookable

  has_hook :create

  ROLES = {
      1 => 'Poor user',
      2 => 'User',
      3 => 'Power user',
      21 => 'Admin',
      90 => 'Super admin',
      99 => 'God',
  }

  def create
    TransactionChains::User::Create.fire(self)
  end

  def lazy_delete(lazy)
    if lazy
      self.m_deleted = Time.new.to_i
      self.m_state = 'deleted'
      save!
    else
      destroy
    end
  end

  def role
    if m_level >= 90
      :admin
    elsif m_level >= 21
      :support
    elsif m_level >= 1
      :user
    end
  end

  def first_name
    m_name.split(' ').first
  end

  def last_name
    m_name.split(' ').last
  end

  def full_name
    m_name.empty? ? m_nick : m_name
  end

  def last_request_at
    m_last_activity ? Time.at(m_last_activity) : 'never'
  end

  def valid_password?(*credentials)
    VpsAdmin::API::CryptoProvider.matches?(m_pass, *credentials)
  end

  def env_config(env, name)
    return @user_env_cfg.method(name).call if @user_env_cfg

    @user_env_cfg = environment_user_configs.find_by(environment: env)
    return @user_env_cfg.method(name).call if @user_env_cfg

    env.method(name).call
  end

  def vps_in_env(env)
    vpses.joins(node: [:location]).where(
        locations: {environment_id: env.id}
    ).count
  end

  def self.authenticate(username, password)
    u = User.find_by(m_nick: username)

    if u
      u if u.valid_password?(username, password)
    end
  end

  def self.current
    Thread.current[:user]
  end

  def self.current=(user)
    Thread.current[:user] = user
  end

  private
  def set_no_password
    self.m_pass = '!' if self.m_pass.nil? || self.m_pass.empty?
  end
end
