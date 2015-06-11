class User < ActiveRecord::Base
  self.table_name = 'members'
  self.primary_key = 'm_id'

  has_many :vpses, :foreign_key => :m_id
  has_many :transactions, foreign_key: :t_m_id
  has_many :storage_exports, foreign_key: :member_id
  has_many :environment_user_configs
  has_many :environments, through: :environment_user_configs
  has_many :datasets
  has_many :user_cluster_resources
  has_many :snapshot_downloads

  before_validation :set_no_password

  alias_attribute :login, :m_nick
  alias_attribute :role, :m_level

  attr_reader :password_plain

  has_paper_trail ignore: [
      :m_last_activity,
  ]

  validates :m_level, :m_nick, :m_pass, presence: true
  validates :m_level, numericality: {
      only_integer: true
  }
  validates :m_nick, format: {
      with: /\A[a-zA-Z0-9\.\-]{3,63}\z/,
      message: 'not a valid login'
  }, uniqueness: true

  include Lockable
  include HaveAPI::Hookable

  has_hook :create

  include VpsAdmin::API::Lifetimes::Model
  set_object_states suspended: {
                        enter: TransactionChains::User::Suspend,
                        leave: TransactionChains::User::Resume
                    },
                    soft_delete: {
                        enter: TransactionChains::User::SoftDelete,
                        leave: TransactionChains::User::Revive
                    },
                    hard_delete: {
                        enter: TransactionChains::User::HardDelete
                    },
                    deleted: {
                        enter: TransactionChains::Lifetimes::NotImplemented
                    }

  default_scope {
    where.not(object_state: object_states[:hard_delete])
  }

  scope :existing, -> {
    unscoped {
      where(object_state: [
                object_states[:active],
                object_states[:suspended]
            ])
    }
  }

  scope :including_deleted, -> {
    unscoped {
      where(object_state: [
                object_states[:active],
                object_states[:suspended],
                object_states[:soft_delete]
            ])
    }
  }

  ROLES = {
      1 => 'Poor user',
      2 => 'User',
      3 => 'Power user',
      21 => 'Admin',
      90 => 'Super admin',
      99 => 'God',
  }

  def create(vps, node, tpl)
    TransactionChains::User::Create.fire(self, vps, node, tpl)
  end

  def destroy(override = false)
    if override
      super
    else
      TransactionChains::User::Destroy.fire(self)
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

  def paid_until
    i = m_paid_until.to_i
    i > 0 ? Time.at(i) : nil
  end

  def last_activity
    i = m_last_activity.to_i
    i > 0 ? Time.at(i) : nil
  end

  def valid_password?(*credentials)
    VpsAdmin::API::CryptoProvider.matches?(m_pass, *credentials)
  end

  def set_password(plaintext)
    @password_plain = plaintext
    self.m_pass = VpsAdmin::API::CryptoProvider.encrypt(login, plaintext)
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
