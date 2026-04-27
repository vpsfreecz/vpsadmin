{
  adminUserId,
  node1Id,
}:
let
  base = import ../storage/remote-common.nix {
    inherit adminUserId node1Id;
    node2Id = node1Id;
    manageCluster = false;
  };
in
base
+ ''
  def setup_user_lifecycle_cluster(services, node)
    [services, node].each(&:start)
    services.wait_for_vpsadmin_api
    wait_for_running_nodectld(node)
    wait_for_node_ready(services, node1_id)
    services.unlock_transaction_signing_key(passphrase: 'test')

    create_pool(
      services,
      node_id: node1_id,
      label: 'user-lifecycle-hv',
      filesystem: primary_pool_fs,
      role: 'hypervisor'
    )
    create_pool(
      services,
      node_id: node1_id,
      label: 'user-lifecycle-primary',
      filesystem: 'tank/user-primary',
      role: 'primary'
    )
    wait_for_pool_online(services, PoolId.for(services, primary_pool_fs))
    wait_for_pool_online(services, PoolId.for(services, 'tank/user-primary'))

    ensure_user_mail_templates(services)
    ensure_user_default_resources(services)
    ensure_user_namespace_blocks(services)
    ensure_user_create_namespace_hook(services)
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

  def ensure_user_mail_templates(services)
    services.api_ruby_json(code: <<~RUBY)
      %w[
        user_create
        user_soft_delete
        user_suspend
        user_resume
        user_revive
        user_new_login
        user_new_token
        user_failed_logins
        user_totp_recovery_code_used
      ].each do |template_name|
        template = MailTemplate.find_or_create_by!(name: template_name) do |tpl|
          tpl.label = template_name.tr('_', ' ').capitalize
          tpl.template_id = template_name
        end

        next if template.mail_template_translations.where(language: Language.first).exists?

        template.mail_template_translations.create!(
          language: Language.first,
          from: 'noreply@test.invalid',
          subject: "\#{template_name} subject",
          text_plain: "\#{template_name} body"
        )
      end

      puts JSON.dump(status: true)
    RUBY
  end

  def ensure_user_default_resources(services)
    services.api_ruby_json(code: <<~RUBY)
      values = {
        cpu: 4,
        memory: 4096,
        diskspace: 20_480,
        swap: 1024
      }

      Environment.find_each do |env|
        values.each do |name, value|
          resource = ClusterResource.find_by!(name: name.to_s)
          DefaultObjectClusterResource.find_or_initialize_by(
            environment: env,
            cluster_resource: resource,
            class_name: 'Vps'
          ).tap do |row|
            row.value = value
            row.save! if row.changed?
          end
        end

        pkg = ClusterResourcePackage.find_or_create_by!(label: "User lifecycle default \#{env.id}")
        values.each do |name, value|
          resource = ClusterResource.find_by!(name: name.to_s)
          ClusterResourcePackageItem.find_or_initialize_by(
            cluster_resource_package: pkg,
            cluster_resource: resource
          ).tap do |item|
            item.value = value
            item.save! if item.changed?
          end
        end

        DefaultUserClusterResourcePackage.find_or_create_by!(
          environment: env,
          cluster_resource_package: pkg
        )
      end

      puts JSON.dump(status: true)
    RUBY
  end

  def ensure_user_namespace_blocks(services, count: 32)
    services.api_ruby_json(code: <<~RUBY)
      size = 65_536
      offset = size * 2

      (1..#{Integer(count)}).each do |i|
        UserNamespaceBlock.find_or_create_by!(index: i) do |block|
          block.offset = offset + ((i - 1) * size)
          block.size = size
        end
      end

      puts JSON.dump(status: true)
    RUBY
  end

  def ensure_user_create_namespace_hook(services)
    services.api_ruby_json(code: <<~RUBY)
      unless defined?($user_lifecycle_create_namespace_hook)
        User.connect_hook(:create) do |ret, user|
          next ret if user.user_namespaces.exists?

          userns = use_chain(TransactionChains::UserNamespace::Allocate, args: [user, 2])
          userns_map = UserNamespaceMap.create_chained!(userns, 'Default map')

          append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
            t.just_create(userns_map)

            UserNamespaceMapEntry.kinds.each_value do |kind|
              t.just_create(UserNamespaceMapEntry.create!(
                user_namespace_map: userns_map,
                kind: kind,
                vps_id: 0,
                ns_id: 0,
                count: userns.size
              ))
            end
          end

          ret
        end

        $user_lifecycle_create_namespace_hook = true
      end

      puts JSON.dump(status: true)
    RUBY
  end

  def create_test_user(services, login:, password:, create_vps: false, activate: true, node_id: nil, os_template_id: nil)
    services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      user = User.new(
        login: #{login.inspect},
        full_name: #{login.inspect},
        email: #{"#{login}@example.test".inspect},
        level: 1,
        language: Language.first,
        enable_basic_auth: true,
        enable_token_auth: true,
        mailer_enabled: true
      )
      user.set_password(#{password.inspect})

      node = #{node_id.nil? ? 'nil' : "Node.find(#{Integer(node_id)})"}
      template = #{os_template_id.nil? ? 'nil' : "OsTemplate.find(#{Integer(os_template_id)})"}

      chain, created = TransactionChains::User::Create.fire(
        user,
        #{create_vps ? 'true' : 'false'},
        node,
        template,
        #{activate ? 'true' : 'false'}
      )

      puts JSON.dump(chain_id: chain&.id, user_id: created.id, login: created.login)
    RUBY
  end

  def set_user_state(services, user_id:, state:, reason: 'user lifecycle test')
    services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      user = User.unscoped.find(#{Integer(user_id)})
      chain = user.set_object_state(
        #{state.inspect}.to_sym,
        reason: #{reason.inspect},
        user: User.current
      )

      puts JSON.dump(chain_id: chain.id, user_id: user.id)
    RUBY
  end

  def user_row(services, user_id)
    services.api_ruby_json(code: <<~RUBY)
      user = User.unscoped.find(#{Integer(user_id)})
      puts JSON.dump(
        id: user.id,
        login: user.login,
        password: user.password,
        object_state: user.object_state,
        environment_user_config_count: user.environment_user_configs.count,
        user_cluster_resource_count: user.user_cluster_resources.count,
        personal_package_count: user.cluster_resource_packages.where(label: 'Personal package').count
      )
    RUBY
  end

  def vps_rows_for_user(services, user_id)
    services.api_ruby_json(code: <<~RUBY)
      rows = Vps.unscoped.where(user_id: #{Integer(user_id)}).order(:id).map do |vps|
        {
          id: vps.id,
          node_id: vps.node_id,
          object_state: vps.object_state,
          is_running: vps.vps_current_status&.is_running,
          user_namespace_map_id: vps.user_namespace_map_id
        }
      end

      puts JSON.dump(rows)
    RUBY
  end

  def first_user_vps(services, user_id)
    vps_rows_for_user(services, user_id).first
  end

  def create_detached_token_session(services, user_id:, label: 'user-token')
    services.api_ruby_json(code: <<~RUBY)
      token = Token.get!(valid_to: Time.now + 3600)
      agent = UserAgent.find_or_create!('v4 user lifecycle')
      session = UserSession.create!(
        user: User.find(#{Integer(user_id)}),
        admin: User.find(#{Integer(admin_user_id)}),
        user_agent: agent,
        auth_type: 'token',
        api_ip_addr: '127.0.0.1',
        api_ip_ptr: 'localhost',
        client_ip_addr: '127.0.0.1',
        client_ip_ptr: 'localhost',
        client_version: 'v4 user lifecycle',
        token: token,
        token_str: token.token,
        token_lifetime: 'renewable_manual',
        token_interval: 3600,
        scope: ['*'],
        label: #{label.inspect}
      )

      puts JSON.dump(id: session.id, token_id: session.token_id)
    RUBY
  end

  def user_sessions_for(services, user_id)
    services.api_ruby_json(code: <<~RUBY)
      puts JSON.dump(UserSession.where(user_id: #{Integer(user_id)}).order(:id).map do |session|
        {
          id: session.id,
          token_id: session.token_id,
          closed_at: session.closed_at&.iso8601
        }
      end)
    RUBY
  end

  def password_auth_result(services, login:, password:)
    services.api_ruby_json(code: <<~RUBY)
      result = VpsAdmin::API::Operations::Authentication::Password.run(
        #{login.inspect},
        #{password.inspect},
        multi_factor: false
      )

      puts JSON.dump(
        found: !result.nil?,
        authenticated: result&.authenticated?,
        complete: result&.complete?
      )
    RUBY
  end

  def create_dns_user_fixture(services, user_id:)
    services.api_ruby_json(code: <<~RUBY)
      user = User.find(#{Integer(user_id)})
      suffix = SecureRandom.hex(4)
      owned_zone = DnsZone.create!(
        name: "owned-\#{suffix}.example.test.",
        user: user,
        zone_role: :forward_role,
        zone_source: :internal_source,
        enabled: true,
        label: "",
        default_ttl: 3600,
        email: 'dns@example.test'
      )
      DnsRecord.create!(
        dns_zone: owned_zone,
        name: 'www',
        record_type: 'A',
        content: '192.0.2.44',
        enabled: true,
        confirmed: DnsRecord.confirmed(:confirmed)
      )
      system_zone = DnsZone.create!(
        name: "system-\#{suffix}.example.test.",
        zone_role: :forward_role,
        zone_source: :internal_source,
        enabled: true,
        label: "",
        default_ttl: 3600,
        email: 'dns@example.test'
      )
      user_record = DnsRecord.create!(
        dns_zone: system_zone,
        user: user,
        name: 'user',
        record_type: 'A',
        content: '192.0.2.45',
        ttl: 3600,
        enabled: true,
        confirmed: DnsRecord.confirmed(:confirmed)
      )

      puts JSON.dump(
        owned_zone_id: owned_zone.id,
        system_zone_id: system_zone.id,
        user_record_id: user_record.id
      )
    RUBY
  end

  def dns_fixture_state(services, dns)
    services.api_ruby_json(code: <<~RUBY)
      owned_zone = DnsZone.unscoped.find_by(id: #{Integer(dns.fetch('owned_zone_id'))})
      user_record = DnsRecord.find_by(id: #{Integer(dns.fetch('user_record_id'))})

      puts JSON.dump(
        owned_zone_exists: !owned_zone.nil?,
        owned_zone_enabled: owned_zone&.enabled,
        owned_zone_original_enabled: owned_zone&.original_enabled,
        user_record_exists: !user_record.nil?,
        user_record_enabled: user_record&.enabled,
        user_record_original_enabled: user_record&.original_enabled
      )
    RUBY
  end

  def export_rows_for_user(services, user_id)
    services.api_ruby_json(code: <<~RUBY)
      puts JSON.dump(Export.unscoped.where(user_id: #{Integer(user_id)}).order(:id).map do |export|
        {
          id: export.id,
          enabled: export.enabled,
          original_enabled: export.original_enabled,
          object_state: export.object_state
        }
      end)
    RUBY
  end

  def create_user_vps_export_dns_fixture(services, login:, password:)
    created = create_test_user(services, login: login, password: password)
    wait_for_vps_chain_done(services, created.fetch('chain_id'))
    vps = create_vps(
      services,
      admin_user_id: created.fetch('user_id'),
      node_id: node1_id,
      hostname: login,
      start: true
    )
    wait_for_vps_running(services, vps.fetch('id'))
    root = dataset_info(services, vps.fetch('id'))
    export = create_export(
      services,
      admin_user_id: admin_user_id,
      dataset_id: root.fetch('dataset_id'),
      enabled: true
    )
    dns = create_dns_user_fixture(services, user_id: created.fetch('user_id'))

    created.merge(vps: vps, export: export, dns: dns)
  end

  def create_hard_delete_user_objects(services, user_id:, vps_id:)
    services.api_ruby_json(code: <<~RUBY)
      user = User.find(#{Integer(user_id)})
      vps = Vps.find(#{Integer(vps_id)})
      snapshot = Snapshot.create!(
        dataset: vps.dataset_in_pool.dataset,
        name: "hard-delete-\#{SecureRandom.hex(4)}",
        history_id: vps.dataset_in_pool.dataset.current_history_id,
        confirmed: Snapshot.confirmed(:confirmed)
      )
      SnapshotInPool.create!(
        snapshot: snapshot,
        dataset_in_pool: vps.dataset_in_pool,
        confirmed: SnapshotInPool.confirmed(:confirmed)
      )
      download = SnapshotDownload.create!(
        user: user,
        snapshot: snapshot,
        from_snapshot: nil,
        pool: vps.dataset_in_pool.pool,
        secret_key: SecureRandom.hex(16),
        file_name: 'download.dat.gz',
        confirmed: SnapshotDownload.confirmed(:confirmed),
        format: :stream,
        object_state: :active,
        expiration_date: Time.now + 7.days
      )
      snapshot.update!(snapshot_download_id: download.id)
      public_key = UserPublicKey.create!(
        user: user,
        label: 'Hard delete key',
        key: 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINixoscreate create@test',
        auto_add: false
      )
      user_data = VpsUserData.create!(
        user: user,
        label: 'Hard delete data',
        format: 'script',
        content: "#!/bin/sh\\necho spec\\n"
      )
      totp = UserTotpDevice.create!(
        user: user,
        label: 'Hard delete TOTP',
        secret: ROTP::Base32.random_base32,
        recovery_code: 'recovery',
        confirmed: true,
        enabled: true
      )
      webauthn = WebauthnCredential.create!(
        user: user,
        external_id: SecureRandom.hex(16),
        public_key: 'public-key',
        label: 'Hard delete WebAuthn',
        sign_count: 0
      )
      tsig = DnsTsigKey.create!(
        user: user,
        name: "hard-delete-\#{SecureRandom.hex(4)}.",
        algorithm: 'hmac-sha256',
        secret: SecureRandom.base64(32)
      )

      puts JSON.dump(
        snapshot_download_id: download.id,
        public_key_id: public_key.id,
        user_data_id: user_data.id,
        totp_id: totp.id,
        webauthn_id: webauthn.id,
        tsig_id: tsig.id
      )
    RUBY
  end

  def hard_delete_artifact_counts(services, ids)
    services.api_ruby_json(code: <<~RUBY)
      puts JSON.dump(
        snapshot_downloads: SnapshotDownload.unscoped.where(id: #{Integer(ids.fetch('snapshot_download_id'))}).count,
        public_keys: UserPublicKey.where(id: #{Integer(ids.fetch('public_key_id'))}).count,
        user_data: VpsUserData.where(id: #{Integer(ids.fetch('user_data_id'))}).count,
        totp_devices: UserTotpDevice.where(id: #{Integer(ids.fetch('totp_id'))}).count,
        webauthn_credentials: WebauthnCredential.where(id: #{Integer(ids.fetch('webauthn_id'))}).count,
        tsig_keys: DnsTsigKey.where(id: #{Integer(ids.fetch('tsig_id'))}).count
      )
    RUBY
  end

  def first_user_namespace(services, user_id)
    services.api_ruby_json(code: <<~RUBY)
      userns = UserNamespace.where(user_id: #{Integer(user_id)}).order(:id).first!
      map = userns.user_namespace_maps.order(:id).first!
      puts JSON.dump(
        user_namespace_id: userns.id,
        map_id: map.id,
        block_ids: userns.user_namespace_blocks.order(:index).pluck(:id)
      )
    RUBY
  end

  def free_user_namespace(services, user_namespace_id:)
    services.api_ruby_json(code: <<~RUBY)
      #{api_session_prelude(admin_user_id)}

      chain, = TransactionChains::UserNamespace::Free.fire(
        UserNamespace.find(#{Integer(user_namespace_id)})
      )

      puts JSON.dump(chain_id: chain.id)
    RUBY
  end

  def namespace_rows(services, user_namespace_id:, map_id:, block_ids:)
    ids = block_ids.map { |id| Integer(id) }.join(',')
    ids = 'NULL' if ids.empty?

    services.api_ruby_json(code: <<~RUBY)
      puts JSON.dump(
        user_namespace_count: UserNamespace.where(id: #{Integer(user_namespace_id)}).count,
        map_count: UserNamespaceMap.where(id: #{Integer(map_id)}).count,
        block_user_namespace_ids: UserNamespaceBlock.where(id: [#{ids}]).order(:id).pluck(:user_namespace_id)
      )
    RUBY
  end

  def expect_osctl_user(node, map_id, exists:)
    wait_until_block_succeeds(name: "osctl user #{map_id} exists=#{exists}") do
      if exists
        node.succeeds("osctl user show #{Integer(map_id)}", timeout: 30)
      else
        node.fails("osctl user show #{Integer(map_id)}", timeout: 30)
      end
      true
    end
  end
''
