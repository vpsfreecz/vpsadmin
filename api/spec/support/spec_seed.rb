# frozen_string_literal: true

module SpecSeed
  module_function

  PASSWORD = 'secret'
  OTHER_USER_LOGIN = 'otheruser'

  def bootstrap!
    seed_language_if_needed!
    seed_users!
    seed_environments!
    seed_locations!
    seed_user_accounts!
  end

  def admin
    @admin ||= User.find_by!(login: 'admin')
  end

  def support
    @support ||= User.find_by!(login: 'support')
  end

  def user
    @user ||= User.find_by!(login: 'user')
  end

  def other_user
    @other_user ||= User.find_by!(login: OTHER_USER_LOGIN)
  end

  def environment
    @environment ||= Environment.find_by!(label: 'Spec Env')
  end

  def other_environment
    @other_environment ||= Environment.find_by!(label: 'Spec Env 2')
  end

  def location
    @location ||= Location.find_by!(label: 'Spec Location A')
  end

  def other_location
    @other_location ||= Location.find_by!(label: 'Spec Location B')
  end

  def seed_language_if_needed!
    return unless User.column_names.include?('language_id')

    Language.find_or_create_by!(code: 'en') do |lang|
      lang.label = 'English'
    end
  end

  def seed_users!
    create_or_update_user!(
      login: 'admin',
      level: 99,
      email: 'admin@test.invalid'
    )

    create_or_update_user!(
      login: 'support',
      level: 21,
      email: 'support@test.invalid'
    )

    create_or_update_user!(
      login: 'user',
      level: 1,
      email: 'user@test.invalid'
    )

    create_or_update_user!(
      login: OTHER_USER_LOGIN,
      level: 1,
      email: 'otheruser@test.invalid'
    )
  end

  def seed_environments!
    Environment.find_or_create_by!(label: 'Spec Env') do |env|
      env.domain = 'spec.test'
      env.user_ip_ownership = false
    end

    Environment.find_or_create_by!(label: 'Spec Env 2') do |env|
      env.domain = 'spec2.test'
      env.user_ip_ownership = false
    end
  end

  def seed_locations!
    Location.find_or_create_by!(label: 'Spec Location A') do |loc|
      loc.environment = environment
      loc.domain = 'spec-loc-a.test'
      loc.has_ipv6 = true
      loc.remote_console_server = ''
      loc.description = 'Spec Location A'
    end

    Location.find_or_create_by!(label: 'Spec Location B') do |loc|
      loc.environment = other_environment
      loc.domain = 'spec-loc-b.test'
      loc.has_ipv6 = false
      loc.remote_console_server = ''
      loc.description = 'Spec Location B'
    end
  end

  def seed_user_accounts!
    conn = ActiveRecord::Base.connection
    ensure_user_accounts_table!(conn)

    user_ids = [admin.id, support.id, user.id, other_user.id]
    existing = conn.select_values(
      "SELECT user_id FROM user_accounts WHERE user_id IN (#{user_ids.join(',')})"
    ).map(&:to_i)
    missing = user_ids - existing
    return if missing.empty?

    now = conn.quote(Time.now)
    missing.each do |user_id|
      conn.execute(
        'INSERT INTO user_accounts (user_id, monthly_payment, paid_until, updated_at) ' \
        "VALUES (#{user_id}, 0, NULL, #{now})"
      )
    end
  end

  def ensure_user_accounts_table!(conn)
    return if conn.data_source_exists?('user_accounts')

    conn.create_table :user_accounts do |t|
      t.integer :user_id, null: false
      t.integer :monthly_payment, null: false, default: 0
      t.datetime :paid_until
      t.datetime :updated_at
    end

    conn.add_index :user_accounts, :user_id, unique: true
  end

  def create_or_update_user!(login:, level:, email:)
    u = User.find_or_initialize_by(login: login)

    u.level = level
    u.email = email

    if u.full_name.nil? || u.full_name.empty?
      u.full_name = login
    end

    u.enable_basic_auth = true
    u.enable_multi_factor_auth = false
    u.password_reset = false
    u.lockout = false

    u.language = language if u.language.nil?

    if u.object_state != 'active'
      u.object_state = 'active'
    end

    set_password!(u, PASSWORD)
    u.save!

    u
  end

  def language
    @language ||= Language.find_by(code: 'en')
  end

  def set_password!(user, password)
    user.set_password(password)
  end
end
