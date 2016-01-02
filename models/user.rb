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

  enum password_version: VpsAdmin::API::CryptoProviders::PROVIDERS

  before_validation :set_no_password

  alias_attribute :login, :m_nick
  alias_attribute :role, :m_level

  attr_reader :password_plain

  has_paper_trail only: %i(m_nick m_level m_name m_mail m_address
                           m_monthly_payment m_mailer_enable object_state
                           expiration_date paid_until)

  validates :m_level, :m_nick, :m_pass, presence: true
  validates :m_level, numericality: {
      only_integer: true
  }
  validates :m_nick, format: {
      with: /\A[a-zA-Z0-9\.\-]{2,63}\z/,
      message: 'not a valid login'
  }, uniqueness: true

  include Lockable
  include HaveAPI::Hookable

  has_hook :create,
      desc: 'Called when a new User is being created',
      context: 'TransactionChains::User::Create instance',
      args: {
          user: 'User instance'
      }

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
      where(object_state: object_states[:active])
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
    m_name.nil? || m_name.empty? ? m_nick : m_name
  end

  def last_request_at
    last_activity_at ? last_activity_at : 'never'
  end

  def set_password(plaintext)
    @password_plain = plaintext

    VpsAdmin::API::CryptoProviders.current do |name, provider|
      self.password_version = name
      self.m_pass = provider.encrypt(login, plaintext)
    end
  end

  def env_config(env, name)
    return @user_env_cfg.method(name).call if @user_env_cfg

    @user_env_cfg = environment_user_configs.find_by(environment: env)
    return @user_env_cfg.method(name).call if @user_env_cfg

    env.method(name).call
  end

  def vps_in_env(env)
    vpses.joins(:node).where(
        servers: {environment_id: env.id},
        vps: {object_state: [
            ::Vps.object_states[:active],
            ::Vps.object_states[:suspended]
        ]}
    ).count
  end


  def resume_login(request)
    self.update!(last_request_at: Time.now)

    User.current = self
  end

  def self.authenticate(request, username, password)
    u = User.unscoped.where(
        object_state: [
            object_states[:active],
            object_states[:suspended],
        ]
    ).find_by('m_nick = ? COLLATE utf8_bin', username)
    return unless u

    c = VpsAdmin::API::CryptoProviders

    if !c.provider(u.password_version).matches?(u.m_pass, u.login, password)
      self.increment_counter(:failed_login_count, u.id)
      return
    end

    self.increment_counter(:login_count, u.id)
    u.update!(
        last_login_at: u.current_login_at,
        current_login_at: Time.now,
        last_login_ip: u.current_login_ip,
        current_login_ip: request.ip
    )

    if c.update?(u.password_version)
      c.current do |name, provider|
        u.update!(
            password_version: name,
            m_pass: provider.encrypt(u.login, password)
        )
      end
    end

    u
  end

  def self.login(*args)
    self.current = authenticate(*args)
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
