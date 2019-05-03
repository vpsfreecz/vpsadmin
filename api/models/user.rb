require 'vpsadmin/api/crypto_providers'
require 'vpsadmin/api/lifetimes'
require_relative 'lockable'
require_relative 'transaction_chains/user/suspend'
require_relative 'transaction_chains/user/resume'
require_relative 'transaction_chains/user/soft_delete'
require_relative 'transaction_chains/user/revive'
require_relative 'transaction_chains/user/hard_delete'
require_relative 'transaction_chains/lifetimes/not_implemented'

class User < ActiveRecord::Base
  has_many :user_namespaces
  has_many :vpses
  has_many :transactions
  has_many :environment_user_configs
  has_many :environments, through: :environment_user_configs
  has_many :datasets
  has_many :user_cluster_resources
  has_many :user_cluster_resource_packages
  has_many :cluster_resource_packages
  has_many :snapshot_downloads
  has_many :ip_traffics
  has_many :ip_recent_traffics
  has_many :user_public_keys
  has_many :user_mail_role_recipients
  has_many :user_mail_template_recipients
  has_many :api_tokens
  belongs_to :language

  enum password_version: VpsAdmin::API::CryptoProviders::PROVIDERS

  before_validation :set_no_password

  alias_attribute :role, :level

  attr_reader :password_plain

  has_paper_trail only: %i(login level full_name email address
                           mailer_enabled object_state expiration_date)

  validates :level, :login, :password, :language_id, presence: true
  validates :level, numericality: {
    only_integer: true
  }
  validates :login, format: {
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
      },
      ret: {
        objects: 'An array of created objects'
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
    if level >= 90
      :admin
    elsif level >= 21
      :support
    elsif level >= 1
      :user
    end
  end

  def first_name
    full_name.split(' ').first
  end

  def last_name
    full_name.split(' ').last
  end

  def last_request_at
    last_activity_at ? last_activity_at : 'never'
  end

  def set_password(plaintext)
    @password_plain = plaintext

    VpsAdmin::API::CryptoProviders.current do |name, provider|
      self.password_version = name
      self.password = provider.encrypt(login, plaintext)
    end

    if password_reset && lockout
      self.password_reset = false
      self.lockout = false
    end
  end

  def env_config(env, name)
    return @user_env_cfg.method(name).call if @user_env_cfg

    @user_env_cfg = environment_user_configs.find_by(environment: env)
    return @user_env_cfg.method(name).call if @user_env_cfg

    env.method(name).call
  end

  def vps_in_env(env)
    vpses.joins(node: [:location]).where(
      locations: {environment_id: env.id},
      vpses: {object_state: [
        ::Vps.object_states[:active],
        ::Vps.object_states[:suspended]
      ]}
    ).count
  end

  def resume_login(request)
    self.update!(last_request_at: Time.now)

    User.current = self
  end

  def calculate_cluster_resources
    self.class.transaction do
      ::Environment.all.each do |env|
        calculate_cluster_resources_in_env(env)
      end
    end
  end

  def calculate_cluster_resources_in_env(env)
    self.class.transaction do
      ucrs = Hash[user_cluster_resources.where(environment: env).map do |ucr|
        ucr.value = 0
        [ucr.cluster_resource_id, ucr]
      end]

      user_cluster_resource_packages.includes(
        cluster_resource_package: [:cluster_resource_package_items]
      ).where(environment: env).each do |user_pkg|
        user_pkg.cluster_resource_package.cluster_resource_package_items.each do |it|
          ucrs[it.cluster_resource_id].value += it.value
        end
      end

      ucrs.each_value { |ucr| ucr.save! }
    end
  end

  # Returns the user and whether he was authenticated
  # @param request [Sinatra::Request]
  # @param username [String]
  # @param password [String]
  # @return [Array(User, Boolean), nil]
  def self.authenticate(request, username, password)
    u = User.unscoped.where(
      object_state: [
        object_states[:active],
        object_states[:suspended],
      ],
    ).find_by('login = ? COLLATE utf8_bin', username)
    return unless u

    provider = VpsAdmin::API::CryptoProviders.provider(u.password_version)
    [u, provider.matches?(u.password, u.login, password)]
  end

  # Authenticate user and log him in
  # @param request [Sinatra::Request]
  # @param username [String]
  # @param password [String]
  # @return [User, nil]
  def self.login(request, username, password)
    u, authenticated = authenticate(request, username, password)

    if u.nil?
      return
    elsif !authenticated
      u.class.increment_counter(:failed_login_count, u.id)
      return
    elsif u.lockout
      raise VpsAdmin::API::Exceptions::AuthenticationError,
            'account is locked out'
    end

    u.class.increment_counter(:login_count, u.id)
    u.last_login_at = u.current_login_at
    u.current_login_at = Time.now
    u.last_login_ip = u.current_login_ip
    u.current_login_ip = request.ip
    u.lockout = true if u.password_reset
    u.save!

    if VpsAdmin::API::CryptoProviders.update?(u.password_version)
      VpsAdmin::API::CryptoProviders.current do |name, provider|
        u.update!(
          password_version: name,
          password: provider.encrypt(u.login, password)
        )
      end
    end

    self.current = u
  end

  def self.current
    Thread.current[:user]
  end

  def self.current=(user)
    Thread.current[:user] = user
  end

  private
  def set_no_password
    self.password = '!' if self.password.nil? || self.password.empty?
  end
end
