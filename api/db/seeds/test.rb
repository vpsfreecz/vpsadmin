# frozen_string_literal: true

# Minimal seed data required for vpsAdmin services to boot in tests and fresh installs.

require 'json'

ActiveRecord::Base.transaction do
  admin_config = JSON.parse(
    File.read(File.expand_path('./test/admin-user.json', __dir__)),
    symbolize_names: true
  )
  tx_key_config = JSON.parse(
    File.read(File.expand_path('./test/transaction-key.json', __dir__)),
    symbolize_names: true
  )

  language = Language.find_by(code: 'en') || Language.order(:id).first
  language ||= Language.create!(code: 'en', label: 'English')

  # Core configuration values expected to exist
  [
    { category: :core, name: :api_url, value: 'http://api.vpsadmin.test', min_user_level: 0 },
    { category: :core, name: :auth_url, value: 'http://api.vpsadmin.test', min_user_level: 0 },
    { category: :core, name: :support_mail, value: 'support@example.invalid', min_user_level: 0 },
    { category: :core, name: :logo_url, value: 'http://webui.vpsadmin.test/logo.png', min_user_level: 0 },
    { category: :core, name: :webauthn_rp_name, value: 'vpsAdmin', min_user_level: 99 },
    { category: :core, name: :transaction_key, value: tx_key_config.fetch(:private), min_user_level: 99 },
    { category: :plugin_payments, name: :fio_api_tokens, value: [], min_user_level: 99 }
  ].each do |cfg|
    record = SysConfig.find_or_initialize_by(category: cfg[:category], name: cfg[:name])
    record.data_type = 'String'
    record.min_user_level = cfg[:min_user_level]
    record.value = cfg[:value]
    record.save!
  end

  # Ensure baseline cluster resources exist
  [
    { name: 'memory', label: 'Memory', min: 1024, max: 12 * 1024, stepsize: 1024, resource_type: :numeric },
    { name: 'swap', label: 'Swap', min: 0, max: 12 * 1024, stepsize: 1024, resource_type: :numeric },
    { name: 'cpu', label: 'CPU', min: 1, max: 8, stepsize: 1, resource_type: :numeric },
    { name: 'diskspace', label: 'Disk space', min: 10 * 1024, max: 2_000 * 1024, stepsize: 10 * 1024, resource_type: :numeric }
  ].each do |res|
    record = ClusterResource.find_or_initialize_by(name: res[:name])
    record.label = res[:label]
    record.min = res[:min]
    record.max = res[:max]
    record.stepsize = res[:stepsize]
    record.resource_type = ClusterResource.resource_types.fetch(res[:resource_type].to_s)
    record.allocate_chain = nil
    record.free_chain = nil
    record.save!
  end

  # Provide a default environment for simple tests
  Environment.find_or_create_by!(id: 1) do |env|
    env.label = 'test'
    env.domain = 'vpsadmin.test'
    env.maintenance_lock = 0
    env.can_create_vps = false
    env.can_destroy_vps = false
    env.vps_lifetime = 0
    env.max_vps_count = 1
    env.user_ip_ownership = false
  end

  admin = User.find_or_initialize_by(login: admin_config.fetch(:login))
  admin.full_name = admin_config.fetch(:full_name)
  admin.email = admin_config.fetch(:email)
  admin.level = 99
  admin.language = language
  admin.enable_basic_auth = true
  admin.enable_token_auth = true
  admin.password_reset = false
  admin.lockout = false
  admin.object_state ||= :active
  admin.set_password(admin_config.fetch(:password))
  admin.save!
end
