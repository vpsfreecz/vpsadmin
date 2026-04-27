# frozen_string_literal: true

require 'securerandom'

module UserLifecycleChainSpecHelpers
  USER_MAIL_TEMPLATES = %w[
    user_create
    user_soft_delete
    user_suspend
    user_resume
    user_revive
    user_new_login
    user_new_token
    user_failed_logins
    user_totp_recovery_code_used
  ].freeze

  def ensure_user_mail_templates!
    USER_MAIL_TEMPLATES.each do |template_name|
      template = MailTemplate.find_or_create_by!(name: template_name) do |tpl|
        tpl.label = template_name.tr('_', ' ').capitalize
        tpl.template_id = template_name
      end

      next if template.mail_template_translations.where(language: SpecSeed.language).exists?

      template.mail_template_translations.create!(
        language: SpecSeed.language,
        from: 'noreply@test.invalid',
        subject: "#{template_name} subject",
        text_plain: "#{template_name} body"
      )
    end
  end

  def ensure_user_namespace_blocks!(count: 8, start_index: 1)
    size = 65_536
    offset = size * 2

    count.times do |i|
      index = start_index + i
      UserNamespaceBlock.find_or_create_by!(index: index) do |block|
        block.offset = offset + ((index - 1) * size)
        block.size = size
      end
    end
  end

  def create_lifecycle_user!(login: nil, email: nil, object_state: :active)
    login ||= "spec-user-#{SecureRandom.hex(4)}"

    User.new(
      login: login,
      full_name: 'Spec User',
      email: email || "#{login}@test.invalid",
      level: 1,
      language: SpecSeed.language,
      enable_basic_auth: true,
      enable_token_auth: true,
      mailer_enabled: true,
      object_state: object_state
    ).tap do |user|
      user.set_password('secret123')
      user.save!
    end
  end

  def create_detached_token_session!(user:, admin: SpecSeed.admin, label: 'spec-token')
    token = Token.get!(valid_to: Time.now + 3600)
    user_agent = UserAgent.find_or_create!('RSpec token')

    UserSession.create!(
      user: user,
      admin: admin,
      user_agent: user_agent,
      auth_type: 'token',
      api_ip_addr: '127.0.0.1',
      api_ip_ptr: 'localhost',
      client_ip_addr: '127.0.0.1',
      client_ip_ptr: 'localhost',
      client_version: 'RSpec',
      token: token,
      token_str: token.token,
      token_lifetime: 'renewable_manual',
      token_interval: 3600,
      scope: ['*'],
      label: label
    )
  end

  def create_user_namespace_with_map!(user:, label: nil, block_count: 1)
    size = 65_536
    userns = UserNamespace.create!(
      user: user,
      block_count: block_count,
      offset: (UserNamespace.maximum(:offset) || 131_072) + size,
      size: size * block_count
    )

    map = UserNamespaceMap.create!(
      user_namespace: userns,
      label: label || "spec-map-#{SecureRandom.hex(4)}"
    )

    create_user_namespace_map_entries!(map)

    [userns, map]
  end

  def create_user_namespace_map_entries!(userns_map, uid_count: nil, gid_count: nil)
    size = userns_map.user_namespace.size

    UserNamespaceMapEntry.create!(
      user_namespace_map: userns_map,
      kind: :uid,
      vps_id: 0,
      ns_id: 0,
      count: uid_count || size
    )
    UserNamespaceMapEntry.create!(
      user_namespace_map: userns_map,
      kind: :gid,
      vps_id: 0,
      ns_id: 0,
      count: gid_count || size
    )
  end

  def attach_blocks_to_user_namespace!(userns, count: userns.block_count)
    ensure_user_namespace_blocks!(count: count + 2)
    UserNamespaceBlock.where(user_namespace_id: nil).order(:index).limit(count).each do |block|
      block.update!(user_namespace: userns)
    end
  end

  def create_user_dns_runtime_fixture!(user:)
    dns_server = create_dns_server!(
      node: SpecSeed.node,
      name: "ns-user-life-#{SecureRandom.hex(3)}"
    )

    owned_zone = create_dns_zone!(
      user: user,
      source: :internal_source,
      name: "owned-#{SecureRandom.hex(4)}.example.test."
    )
    create_dns_server_zone!(dns_zone: owned_zone, dns_server: dns_server)
    owned_record = create_dns_record!(
      dns_zone: owned_zone,
      name: 'www',
      content: '192.0.2.21',
      enabled: true
    )

    system_zone = create_dns_zone!(
      user: nil,
      source: :internal_source,
      name: "system-#{SecureRandom.hex(4)}.example.test."
    )
    create_dns_server_zone!(dns_zone: system_zone, dns_server: dns_server)
    user_record = DnsRecord.create!(
      dns_zone: system_zone,
      user: user,
      name: 'user',
      record_type: 'A',
      content: '192.0.2.22',
      ttl: 3600,
      enabled: true,
      confirmed: DnsRecord.confirmed(:confirmed)
    )

    {
      dns_server: dns_server,
      owned_zone: owned_zone,
      owned_record: owned_record,
      system_zone: system_zone,
      user_record: user_record
    }
  end

  def create_user_lifecycle_fixture!(user: create_lifecycle_user!, token_session: true)
    ensure_available_node_status!(SpecSeed.node)
    fixture = build_standalone_vps_fixture(user: user, hostname: "user-life-#{SecureRandom.hex(4)}")
    export, = create_export_for_dataset!(
      dataset_in_pool: fixture.fetch(:dataset_in_pool),
      user: user,
      enabled: true
    )
    dns = create_user_dns_runtime_fixture!(user: user)
    session = create_detached_token_session!(user: user) if token_session

    fixture.merge(
      user: user,
      export: export,
      token_session: session
    ).merge(dns)
  end

  def create_auth_cleanup_fixture!(user:)
    session = create_detached_token_session!(user: user, label: 'cleanup-token')
    sso = Token.for_new_record!(Time.now + 3600) do |token|
      SingleSignOn.create!(user: user, token: token)
    end
    metrics_token = MetricsAccessToken.create_for!(user, 'spec_metrics_')
    user_agent = UserAgent.find_or_create!('RSpec OAuth')
    device_token = Token.get!(valid_to: Time.now + 3600)
    device = UserDevice.create!(
      user: user,
      user_agent: user_agent,
      token: device_token,
      client_ip_addr: '127.0.0.1',
      client_ip_ptr: 'localhost',
      last_seen_at: Time.now
    )
    client = Oauth2Client.new(
      name: 'Spec OAuth client',
      client_id: "spec-#{SecureRandom.hex(4)}",
      redirect_uri: 'https://example.test/callback'
    )
    client.set_secret('secret')
    client.save!
    authorization = Oauth2Authorization.create!(
      oauth2_client: client,
      user: user,
      user_session: session,
      single_sign_on: sso,
      user_agent: user_agent,
      user_device: device,
      code: Token.get!(valid_to: Time.now + 300),
      refresh_token: Token.get!(valid_to: Time.now + 3600),
      scope: ['*'],
      client_ip_addr: '127.0.0.1'
    )

    {
      token_session: session,
      single_sign_on: sso,
      metrics_access_token: metrics_token,
      oauth2_authorization: authorization
    }
  end

  def create_failed_login!(user:, created_at: Time.now)
    UserFailedLogin.create!(
      user: user,
      user_agent: UserAgent.find_or_create!('RSpec failed login'),
      auth_type: 'basic',
      api_ip_addr: '127.0.0.1',
      client_version: 'RSpec',
      reason: 'invalid password',
      created_at: created_at
    )
  end
end

RSpec.configure do |config|
  config.include UserLifecycleChainSpecHelpers
end
