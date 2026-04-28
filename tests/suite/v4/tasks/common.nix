{
  adminUserId,
  node1Id,
  node2Id ? node1Id,
  manageCluster ? false,
}:
let
  base = import ../network/common.nix {
    inherit
      adminUserId
      node1Id
      node2Id
      manageCluster
      ;
  };
in
base
+ ''
  def env_exports(env)
    env.map { |k, v| "#{k}=#{Shellwords.escape(v.to_s)}" }.join(' ')
  end

  def run_api_rake_task(services, task:, env: {}, expect_success: true, timeout: 300)
    exports = env_exports(env.merge('RACK_ENV' => 'production'))
    cmd = <<~SH
      set -euo pipefail
      api_dir="$(systemctl show -p WorkingDirectory --value vpsadmin-api)"
      api_root="$(dirname "$api_dir")"
      cd "$api_dir"
      #{exports} "$api_root/ruby-env/bin/bundle" exec rake #{Shellwords.escape(task)}
    SH

    expect_success ? services.succeeds(cmd, timeout: timeout) : services.fails(cmd, timeout: timeout)
  end

  def setup_tasks_cluster(services, node, pool_label: 'tasks-hv')
    [services, node].each(&:start)
    services.wait_for_vpsadmin_api
    wait_for_running_nodectld(node)
    wait_for_node_ready(services, node1_id)
    services.unlock_transaction_signing_key(passphrase: 'test')

    create_pool(
      services,
      node_id: node1_id,
      label: pool_label,
      filesystem: primary_pool_fs,
      role: 'hypervisor'
    )
    wait_for_pool_online(services, PoolId.for(services, primary_pool_fs))
    ensure_task_mail_templates(services)
  end

  module PoolId
    def self.for(services, filesystem)
      services.mysql_json_rows(sql: <<~SQL).first.fetch('id')
        SELECT JSON_OBJECT('id', id)
        FROM pools
        WHERE filesystem = #{filesystem.inspect}
        LIMIT 1
      SQL
    end
  end

  def ensure_task_mail_templates(services)
    services.api_ruby_json(code: <<~RUBY)
      %w[
        user_failed_logins
        vps_dataset_expanded
        vps_dataset_shrunk
        vps_stopped_over_quota
      ].each do |name|
        template = MailTemplate.find_or_create_by!(name: name) do |tpl|
          tpl.label = name.tr('_', ' ').capitalize
          tpl.template_id = name
        end

        next if template.mail_template_translations.where(language: Language.first).exists?

        template.mail_template_translations.create!(
          language: Language.first,
          from: 'noreply@test.invalid',
          subject: name + ' subject',
          text_plain: name + ' body'
        )
      end

      puts JSON.dump(ok: true)
    RUBY
  end

  def max_transaction_chain_id(services)
    services.mysql_scalar(sql: 'SELECT COALESCE(MAX(id), 0) FROM transaction_chains').to_i
  end

  def wait_for_chain_after(services, before_id:, type:, label:)
    chain_id = nil

    wait_until_block_succeeds(name: "chain #{type} after #{before_id}") do
      row = services.mysql_json_rows(sql: <<~SQL).first
        SELECT JSON_OBJECT('id', id)
        FROM transaction_chains
        WHERE id > #{Integer(before_id)}
          AND type = #{type.inspect}
        ORDER BY id
        LIMIT 1
      SQL
      expect(row).not_to be_nil
      chain_id = row.fetch('id')
      true
    end

    final_state = wait_for_vps_chain_done(services, chain_id)
    details = chain_failure_details(services, chain_id)
    expect(final_state).to eq(services.class::CHAIN_STATES[:done]), {
      label: label,
      chain_id: chain_id,
      final_state: final_state,
      details: details
    }.inspect
    chain_id
  end

  def create_auth_session_housekeeping_fixture(services)
    ids = services.api_ruby_json(code: <<~RUBY)
      u = User.find(#{admin_user_id})
      ua = UserAgent.find_or_create!('Integration housekeeping')
      token = ->(time) { Token.get!(valid_to: time) }
      ip = {
        api_ip_addr: '127.0.0.1',
        api_ip_ptr: 'localhost',
        client_ip_addr: '127.0.0.1',
        client_ip_ptr: 'localhost',
        client_version: 'integration'
      }
      client = Oauth2Client.create!(
        name: 'Integration OAuth',
        client_id: 'integration-' + SecureRandom.hex(8),
        redirect_uri: 'https://example.test/callback',
        client_secret_hash: 'integration-secret-hash'
      )

      auth_token = AuthToken.create!(
        ip.merge(user: u, user_agent: ua, token: token.call(2.hours.ago), purpose: :mfa)
      )
      detached_oauth = Oauth2Authorization.create!(
        oauth2_client: client, user: u, user_agent: ua, code: token.call(2.hours.ago),
        scope: ['*'], client_ip_addr: '127.0.0.1'
      )
      auth_challenge = WebauthnChallenge.create!(
        ip.merge(
          user: u, user_agent: ua, token: token.call(2.hours.ago),
          challenge_type: :authentication, challenge: SecureRandom.hex(32)
        )
      )
      session = {
        user: u,
        admin: u,
        user_agent: ua,
        auth_type: 'token',
        api_ip_addr: '127.0.0.1',
        client_version: 'integration',
        token_lifetime: :renewable_manual,
        token_interval: 3600,
        scope: ['*']
      }
      closing_session = UserSession.create!(
        session.merge(token: token.call(2.hours.ago), token_str: SecureRandom.hex(10))
      )
      refreshable_session = UserSession.create!(
        session.merge(token: token.call(2.hours.ago), token_str: SecureRandom.hex(10))
      )

      sso = Token.for_new_record!(2.hours.ago) do |token|
        SingleSignOn.create!(user: u, token: token)
      end
      device = UserDevice.create!(
        user: u, user_agent: ua, token: token.call(2.hours.ago),
        client_ip_addr: '127.0.0.1', client_ip_ptr: 'localhost', last_seen_at: Time.now.utc
      )
      refreshable_oauth = Oauth2Authorization.create!(
        oauth2_client: client, user: u, user_session: refreshable_session,
        single_sign_on: sso, user_device: device, user_agent: ua,
        code: token.call(1.hour.from_now), refresh_token: token.call(1.hour.from_now),
        scope: ['*'], client_ip_addr: '127.0.0.1'
      )

      failed = 2.times.map do
        UserFailedLogin.create!(
          ip.merge(user: u, user_agent: ua, auth_type: 'basic', reason: 'invalid password')
        ).id
      end

      puts JSON.dump([
        auth_token.id,
        detached_oauth.id,
        auth_challenge.id,
        closing_session.id,
        refreshable_session.id,
        refreshable_oauth.id,
        sso.id,
        device.id,
        failed
      ])
    RUBY

    {
      'auth_token_id' => ids.fetch(0),
      'detached_oauth_id' => ids.fetch(1),
      'auth_challenge_id' => ids.fetch(2),
      'closing_session_id' => ids.fetch(3),
      'refreshable_session_id' => ids.fetch(4),
      'refreshable_oauth_id' => ids.fetch(5),
      'sso_id' => ids.fetch(6),
      'device_id' => ids.fetch(7),
      'failed_login_ids' => ids.fetch(8)
    }
  end

  def auth_session_housekeeping_rows(services, fixture)
    failed_ids = fixture.fetch('failed_login_ids').map { |id| Integer(id) }
    values = services.api_ruby_json(code: <<~RUBY)
      closing = UserSession.find(#{Integer(fixture.fetch('closing_session_id'))})
      refreshable = UserSession.find(#{Integer(fixture.fetch('refreshable_session_id'))})
      oauth = Oauth2Authorization.find(#{Integer(fixture.fetch('refreshable_oauth_id'))})
      sso = SingleSignOn.find(#{Integer(fixture.fetch('sso_id'))})
      device = UserDevice.find(#{Integer(fixture.fetch('device_id'))})
      failed_ids = #{failed_ids.inspect}

      puts JSON.dump([
        AuthToken.exists?(#{Integer(fixture.fetch('auth_token_id'))}),
        Oauth2Authorization.exists?(#{Integer(fixture.fetch('detached_oauth_id'))}),
        WebauthnChallenge.exists?(#{Integer(fixture.fetch('auth_challenge_id'))}),
        !closing.closed_at.nil?,
        closing.token_id,
        !refreshable.closed_at.nil?,
        refreshable.token_id,
        oauth.refresh_token_id,
        sso.token_id,
        device.token_id,
        UserFailedLogin.where(id: failed_ids).where.not(reported_at: nil).count,
        TransactionChain.where(type: 'TransactionChains::User::ReportFailedLogins').count
      ])
    RUBY

    {
      'auth_token_exists' => values.fetch(0),
      'detached_oauth_exists' => values.fetch(1),
      'auth_challenge_exists' => values.fetch(2),
      'closing_session_closed' => values.fetch(3),
      'closing_session_token_id' => values.fetch(4),
      'refreshable_session_closed' => values.fetch(5),
      'refreshable_session_token_id' => values.fetch(6),
      'refreshable_oauth_refresh_token_id' => values.fetch(7),
      'sso_token_id' => values.fetch(8),
      'device_token_id' => values.fetch(9),
      'reported_failed_login_count' => values.fetch(10),
      'report_chain_count' => values.fetch(11)
    }
  end

  def set_dataset_referenced_for_task(services, dataset_id:, value:)
    services.api_ruby_json(code: <<~RUBY)
      DatasetProperty.where(
        dataset_id: #{Integer(dataset_id)},
        name: 'referenced'
      ).find_each { |prop| prop.update!(value: #{Integer(value)}) }

      puts JSON.dump(ok: true)
    RUBY
  end

  def set_vps_current_status_for_task(services, vps_id:, running:, uptime:)
    services.api_ruby_json(code: <<~RUBY)
      status = VpsCurrentStatus.find_or_initialize_by(vps_id: #{Integer(vps_id)})
      status.update!(
        status: true,
        is_running: #{running ? 'true' : 'false'},
        uptime: #{Integer(uptime)},
        update_count: [status.update_count.to_i, 1].max
      )

      puts JSON.dump(ok: true)
    RUBY
  end

  def create_reverse_dns_zone_runtime(services, name:, network_address:, network_prefix:)
    services.api_ruby_json(code: <<~RUBY)
      zone = DnsZone.create!(
        name: #{name.inspect},
        zone_source: :internal_source,
        zone_role: :reverse_role,
        default_ttl: 3600,
        email: 'dns@example.test',
        enabled: true,
        label: "",
        reverse_network_address: #{network_address.inspect},
        reverse_network_prefix: #{Integer(network_prefix)}
      )

      puts JSON.dump(id: zone.id, name: zone.name)
    RUBY
  end

  def set_host_ip_reverse_record(services, host_ip_id:, dns_record_id:)
    services.api_ruby_json(code: <<~RUBY)
      host_ip = HostIpAddress.find(#{Integer(host_ip_id)})
      host_ip.update!(reverse_dns_record: DnsRecord.find(#{Integer(dns_record_id)}))

      puts JSON.dump(id: host_ip.id, reverse_dns_record_id: host_ip.reverse_dns_record_id)
    RUBY
  end

  def update_dns_record_content_without_runtime(services, dns_record_id:, content:)
    services.api_ruby_json(code: <<~RUBY)
      record = DnsRecord.find(#{Integer(dns_record_id)})
      record.update_column(:content, #{content.inspect})

      puts JSON.dump(id: record.id, content: record.reload.content)
    RUBY
  end
''
