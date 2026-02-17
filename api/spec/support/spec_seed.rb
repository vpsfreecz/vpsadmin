# frozen_string_literal: true

module SpecSeed
  module_function

  PASSWORD = 'secret'
  OTHER_USER_LOGIN = 'otheruser'

  def bootstrap!
    seed_language_if_needed!
    seed_users!
    seed_environments!
    seed_environment_user_configs!
    seed_user_cluster_resources!
    seed_locations!
    seed_networks!
    seed_dns_resolvers!
    seed_nodes!
    seed_pools!
    seed_os_templates!
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

  def node
    @node ||= Node.find_by!(name: 'spec-node-a')
  end

  def other_node
    @other_node ||= Node.find_by!(name: 'spec-node-b')
  end

  def pool
    @pool ||= Pool.find_by!(filesystem: 'spec_pool_a')
  end

  def other_pool
    @other_pool ||= Pool.find_by!(filesystem: 'spec_pool_b')
  end

  def dns_resolver
    @dns_resolver ||= DnsResolver.find_by!(label: 'Spec DNS A')
  end

  def other_dns_resolver
    @other_dns_resolver ||= DnsResolver.find_by!(label: 'Spec DNS B')
  end

  def network_v4
    @network_v4 ||= Network.find_by!(address: '192.0.2.0', prefix: 24)
  end

  def network_v6
    @network_v6 ||= Network.find_by!(address: '2001:db8::', prefix: 64)
  end

  def os_family
    @os_family ||= OsFamily.find_by!(label: 'Spec OS')
  end

  def os_template
    @os_template ||= OsTemplate.find_by!(label: 'Spec OS Template')
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

  def seed_environment_user_configs!
    users = [admin, support, user, other_user]
    environments = [environment, other_environment]

    users.each do |seeded_user|
      environments.each do |env|
        EnvironmentUserConfig.find_or_create_by!(environment: env, user: seeded_user)
      end
    end
  end

  def seed_networks!
    net_v4 = Network.find_or_initialize_by(address: '192.0.2.0', prefix: 24)
    net_v4.assign_attributes(
      label: 'Spec Net v4',
      ip_version: 4,
      role: :public_access,
      managed: true,
      split_access: :no_access,
      split_prefix: 32,
      purpose: :any,
      primary_location: location
    )
    net_v4.save! if net_v4.changed?

    loc_net_v4 = LocationNetwork.find_or_initialize_by(location: location, network: net_v4)
    loc_net_v4.assign_attributes(
      primary: true,
      priority: 10,
      autopick: true,
      userpick: true
    )
    loc_net_v4.save! if loc_net_v4.changed?

    net_v6 = Network.find_or_initialize_by(address: '2001:db8::', prefix: 64)
    net_v6.assign_attributes(
      label: 'Spec Net v6',
      ip_version: 6,
      role: :public_access,
      managed: true,
      split_access: :no_access,
      split_prefix: 128,
      purpose: :vps,
      primary_location: other_location
    )
    net_v6.save! if net_v6.changed?

    loc_net_v6 = LocationNetwork.find_or_initialize_by(location: other_location, network: net_v6)
    loc_net_v6.assign_attributes(
      primary: true,
      priority: 10,
      autopick: true,
      userpick: true
    )
    loc_net_v6.save! if loc_net_v6.changed?
  end

  def seed_dns_resolvers!
    resolver_a = DnsResolver.find_or_initialize_by(label: 'Spec DNS A')
    resolver_a.assign_attributes(
      addrs: '192.0.2.53',
      is_universal: true,
      location: nil,
      ip_version: 4
    )
    resolver_a.save! if resolver_a.changed?

    resolver_b = DnsResolver.find_or_initialize_by(label: 'Spec DNS B')
    resolver_b.assign_attributes(
      addrs: '192.0.2.54',
      is_universal: false,
      location: location,
      ip_version: 4
    )
    resolver_b.save! if resolver_b.changed?
  end

  def seed_nodes!
    Node.find_or_create_by!(name: 'spec-node-a') do |node|
      node.location = location
      node.role = :node
      node.hypervisor_type = :vpsadminos
      node.ip_addr = '192.0.2.101'
      node.max_vps = 10
      node.cpus = 4
      node.total_memory = 4096
      node.total_swap = 1024
      node.active = true
    end

    Node.find_or_create_by!(name: 'spec-node-b') do |node|
      node.location = other_location
      node.role = :storage
      node.hypervisor_type = :vpsadminos
      node.ip_addr = '192.0.2.102'
      node.max_vps = 5
      node.cpus = 8
      node.total_memory = 8192
      node.total_swap = 2048
      node.active = true
    end
  end

  def seed_pools!
    pool_a = Pool.find_or_initialize_by(filesystem: 'spec_pool_a')
    pool_a.assign_attributes(
      node: node,
      label: 'Spec Pool A',
      role: :hypervisor
    )
    pool_a.save! if pool_a.changed?

    pool_b = Pool.find_or_initialize_by(filesystem: 'spec_pool_b')
    pool_b.assign_attributes(
      node: other_node,
      label: 'Spec Pool B',
      role: :hypervisor
    )
    pool_b.save! if pool_b.changed?
  end

  def seed_user_cluster_resources!
    users = [admin, support, user, other_user]
    environments = [environment, other_environment]
    resources = %w[ipv4 ipv4_private ipv6].map { |name| ClusterResource.find_by!(name: name) }

    users.each do |seeded_user|
      environments.each do |env|
        resources.each do |resource|
          record = UserClusterResource.find_or_initialize_by(
            user: seeded_user,
            environment: env,
            cluster_resource: resource
          )
          record.value = 10_000
          record.save! if record.changed?
        end
      end
    end
  end

  def seed_os_templates!
    family = OsFamily.find_or_create_by!(label: 'Spec OS')
    template = OsTemplate.find_or_initialize_by(label: 'Spec OS Template')
    template.assign_attributes(
      os_family: family,
      distribution: 'specos',
      version: '1',
      arch: 'x86_64',
      vendor: 'spec',
      variant: 'base',
      hypervisor_type: :vpsadminos,
      config: {}
    )
    template.save! if template.changed?
  end

  def seed_user_accounts!
    return unless SpecPlugins.enabled?(:payments)

    conn = ActiveRecord::Base.connection
    return unless conn.data_source_exists?('user_accounts')

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
