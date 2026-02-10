# frozen_string_literal: true

module SpecSeed
  module_function

  PASSWORD = 'secret'
  OTHER_USER_LOGIN = 'otheruser'

  def bootstrap!
    seed_language_if_needed!
    seed_users!
    seed_environments!
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
      env.user_ip_ownership = false if env.respond_to?(:user_ip_ownership=)
    end

    Environment.find_or_create_by!(label: 'Spec Env 2') do |env|
      env.domain = 'spec2.test'
      env.user_ip_ownership = false if env.respond_to?(:user_ip_ownership=)
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

    u.level = level if u.respond_to?(:level=)
    u.email = email if u.respond_to?(:email=)

    if u.respond_to?(:full_name=) && (u.full_name.nil? || u.full_name.empty?)
      u.full_name = login
    end

    u.enable_basic_auth = true if u.respond_to?(:enable_basic_auth=)
    u.enable_multi_factor_auth = false if u.respond_to?(:enable_multi_factor_auth=)
    u.password_reset = false if u.respond_to?(:password_reset=)
    u.lockout = false if u.respond_to?(:lockout=)

    if u.respond_to?(:language=) && u.language.nil?
      u.language = language
    elsif u.respond_to?(:language_id=) && u.language_id.nil?
      u.language_id = language&.id
    end

    if u.respond_to?(:object_state=) && u.object_state != 'active'
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
    if user.respond_to?(:set_password)
      user.set_password(password)
      return
    end

    if user.respond_to?(:password=)
      user.password = password
      return
    end

    raise "Don't know how to set password for User; implement SpecSeed.set_password! based on app models"
  end
end
