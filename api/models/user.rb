require 'vpsadmin/api/crypto_providers'
require 'vpsadmin/api/lifetimes'
require_relative 'lockable'
require_relative 'transaction_chains/user/suspend'
require_relative 'transaction_chains/user/resume'
require_relative 'transaction_chains/user/soft_delete'
require_relative 'transaction_chains/user/revive'
require_relative 'transaction_chains/user/hard_delete'
require_relative 'transaction_chains/lifetimes/not_implemented'

class User < ApplicationRecord
  has_many :user_namespaces
  has_many :vpses
  has_many :vps_user_data
  has_many :transaction_chains
  has_many :transactions
  has_many :environment_user_configs
  has_many :environments, through: :environment_user_configs
  has_many :datasets
  has_many :exports
  has_many :user_cluster_resources
  has_many :user_cluster_resource_packages
  has_many :cluster_resource_packages
  has_many :snapshot_downloads
  has_many :user_public_keys
  has_many :user_mail_role_recipients
  has_many :user_mail_template_recipients
  has_many :user_totp_devices
  has_many :auth_tokens
  has_many :user_sessions
  has_many :user_devices
  has_many :oauth2_authorizations
  has_many :single_sign_ons
  has_many :webauthn_credentials
  has_many :webauthn_challenges
  has_many :password_recoveries
  has_many :password_change_logs
  has_many :user_failed_logins
  has_many :metrics_access_tokens
  has_many :dns_zones
  has_many :dns_tsig_keys
  has_many :dns_records
  has_many :dns_record_logs
  belongs_to :language

  enum :password_version, VpsAdmin::API::CryptoProviders::PROVIDERS

  before_validation :set_no_password
  before_validation :normalize_time_zone
  before_update :advance_authentication_generation, if: :will_save_change_to_password?
  after_update :invalidate_auth_tokens, if: :saved_change_to_password?
  after_update :record_password_change, if: :saved_change_to_password?
  after_update :invalidate_password_recoveries_after_role_change,
               if: :saved_change_to_level?
  after_update :invalidate_password_recoveries_after_mfa_disable,
               if: :saved_change_to_enable_multi_factor_auth?

  alias_attribute :role, :level

  attr_reader :password_plain, :recorded_password_change

  has_paper_trail only: %i[login level full_name email address time_zone
                           mailer_enabled object_state expiration_date]

  validates :level, :login, :password, :language_id, presence: true
  validates :level, numericality: {
    only_integer: true
  }
  validates :login, format: {
    with: /\A[a-zA-Z0-9.-]{2,63}\z/,
    message: 'not a valid login'
  }, uniqueness: true
  validates :preferred_session_length, numericality: {
    only_integer: true,
    greater_or_equal_than: 0
  }
  validate :check_time_zone

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

  default_scope do
    where.not(object_state: object_states[:hard_delete])
  end

  scope :existing, lambda {
    unscoped do
      where(object_state: object_states[:active])
    end
  }

  scope :including_deleted, lambda {
    unscoped do
      where(object_state: [
              object_states[:active],
              object_states[:suspended],
              object_states[:soft_delete]
            ])
    end
  }

  ROLES = {
    1 => 'Poor user',
    2 => 'User',
    3 => 'Power user',
    21 => 'Admin',
    90 => 'Super admin',
    99 => 'God'
  }.freeze

  AUTHENTICATION_OBJECT_STATES = %w[active suspended].freeze

  def self.role_for_level(level)
    if level.to_i >= 90
      :admin
    elsif level.to_i >= 21
      :support
    elsif level.to_i >= 1
      :user
    end
  end

  def role
    self.class.role_for_level(level)
  end

  def authentication_allowed_by_lifecycle?
    requested_state = current_object_state&.state

    AUTHENTICATION_OBJECT_STATES.include?(object_state) &&
      (requested_state.nil? || AUTHENTICATION_OBJECT_STATES.include?(requested_state))
  end

  # Authentication authority creation holds this same row lock. Keep it until
  # the requested lifecycle state is published so neither change can pass the
  # other one's final eligibility check.
  def set_object_state(...)
    with_lifecycle_lock { super }
  end

  def record_object_state_change(...)
    with_lifecycle_lock { super }
  end

  def set_expiration(...)
    with_lifecycle_lock do
      ensure_no_pending_lifecycle_change!
      super
    end
  end

  def set_remind_after(...)
    with_lifecycle_lock do
      ensure_no_pending_lifecycle_change!
      super
    end
  end

  def dokuwiki_groups
    if level >= 90
      'admin,user'
    else
      'user'
    end
  end

  def first_name
    full_name.split.first
  end

  def last_name
    full_name.split.last
  end

  def last_request_at
    last_activity_at || 'never'
  end

  def set_password(
    plaintext,
    resolve_password_reset: true,
    source: :other,
    user_session: ::UserSession.current,
    client_ip_addr: nil,
    client_ip_ptr: nil,
    user_agent: nil
  )
    set_password_change_context(
      source:,
      user_session:,
      client_ip_addr:,
      client_ip_ptr:,
      user_agent:
    )

    @password_plain = plaintext

    VpsAdmin::API::CryptoProviders.current do |name, provider|
      self.password_version = name
      self.password = provider.encrypt(login, plaintext)
    end

    password_recoveries.active.update_all(invalidated_at: Time.current) if persisted?

    return if !password_reset || !resolve_password_reset

    self.password_reset = false
    self.lockout = false
  end

  def set_password_change_context(
    source:,
    user_session:,
    client_ip_addr: nil,
    client_ip_ptr: nil,
    user_agent: nil
  )
    normalized_source = source.to_sym
    unless VpsAdmin::API::PasswordChanges::SOURCES.include?(normalized_source)
      raise ArgumentError, "unsupported password change source: #{source.inspect}"
    end

    @password_change_source = normalized_source
    @recorded_password_change = nil
    @password_change_client_ip_addr = nil
    @password_change_client_ip_ptr = nil
    @password_change_user_agent = nil
    return unless persisted?

    @password_change_user_session = user_session
    @password_change_user_session_set = true
    if client_ip_addr || client_ip_ptr || user_agent
      @password_change_client_ip_addr = client_ip_addr
      @password_change_client_ip_ptr = client_ip_ptr
      @password_change_user_agent = user_agent
    elsif user_session
      if user_session.client_ip_addr.present?
        @password_change_client_ip_addr = user_session.client_ip_addr
        @password_change_client_ip_ptr = user_session.client_ip_ptr
      else
        @password_change_client_ip_addr = user_session.api_ip_addr
        @password_change_client_ip_ptr = user_session.api_ip_ptr
      end
      @password_change_user_agent = user_session.user_agent
    end
  end

  def normalize_time_zone
    self.time_zone = nil if time_zone == ''
  end

  def invalidate_auth_tokens
    auth_tokens.destroy_all
  end

  def advance_authentication_generation
    self.authentication_generation += 1
  end

  def record_password_change
    source = @password_change_source || :other
    user_session = if @password_change_user_session_set
                     @password_change_user_session
                   else
                     ::UserSession.current
                   end

    @recorded_password_change = PasswordChangeLog.create!(
      user: self,
      user_session:,
      client_ip_addr: @password_change_client_ip_addr,
      client_ip_ptr: @password_change_client_ip_ptr,
      user_agent: @password_change_user_agent,
      source:
    )
    PasswordEventCounter.record_password_change!(source)
  ensure
    @password_change_source = nil
    @password_change_user_session = nil
    @password_change_user_session_set = false
    @password_change_client_ip_addr = nil
    @password_change_client_ip_ptr = nil
    @password_change_user_agent = nil
  end

  def invalidate_password_recoveries_after_role_change
    previous_level, current_level = saved_change_to_level
    was_eligible = self.class.role_for_level(previous_level) == :user
    is_eligible = self.class.role_for_level(current_level) == :user
    return if was_eligible == is_eligible

    password_recoveries.active.update_all(invalidated_at: Time.current)
  end

  def invalidate_password_recoveries_after_mfa_disable
    return if enable_multi_factor_auth?

    password_recoveries.active.update_all(invalidated_at: Time.current)
    auth_tokens.destroy_all
  end

  def check_time_zone
    return if VpsAdmin::API::TimeZones.valid?(time_zone)

    errors.add(:time_zone, 'is not a valid time zone')
  end

  def env_config(env, name)
    return @user_env_cfg.method(name).call if @user_env_cfg

    @user_env_cfg = environment_user_configs.find_by(environment: env)
    return @user_env_cfg.method(name).call if @user_env_cfg

    env.method(name).call
  end

  def vps_in_env(env)
    vpses.joins(node: [:location]).where(
      locations: { environment_id: env.id },
      vpses: { object_state: [
        ::Vps.object_states[:active],
        ::Vps.object_states[:suspended]
      ] }
    ).count
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
      ucrs = user_cluster_resources.where(environment: env).to_h do |ucr|
        ucr.value = 0
        [ucr.cluster_resource_id, ucr]
      end

      user_cluster_resource_packages.includes(
        cluster_resource_package: [:cluster_resource_package_items]
      ).where(environment: env).each do |user_pkg|
        user_pkg.cluster_resource_package.cluster_resource_package_items.each do |item|
          ucrs[item.cluster_resource_id].value += item.value
        end
      end

      ucrs.each_value(&:save!)
    end
  end

  def self.current
    Thread.current[:user]
  end

  def self.current=(user)
    Thread.current[:user] = user
  end

  private

  # Lock through a separate model instance. ActiveRecord's #with_lock reloads
  # +self+ and clears its association cache, which can discard unsaved changes
  # held by transaction-chain callers before they publish a lifecycle change.
  def with_lifecycle_lock
    self.class.transaction do
      locked_user = self.class.unscoped.lock.find(id)

      self.object_state = locked_user.object_state
      self.expiration_date = locked_user.expiration_date
      self.remind_after_date = locked_user.remind_after_date

      yield
    end
  end

  def ensure_no_pending_lifecycle_change!
    requested_state = current_object_state&.state
    return if requested_state.nil? || requested_state == object_state

    raise ResourceLocked.new(self, 'user lifecycle change is pending')
  end

  def set_no_password
    self.password = '!' if password.nil? || password.empty?
  end
end
