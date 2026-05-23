# frozen_string_literal: true

require 'base64'
require 'securerandom'

RSpec.describe 'API lifecycle bypass regressions' do # rubocop:disable RSpec/DescribeClass
  before do
    header 'Accept', 'application/json'
    SpecSeed.admin
    SpecSeed.user
    SpecSeed.other_user
    SpecSeed.node
    SpecSeed.other_node
    SpecSeed.pool
    SpecSeed.other_pool
    SpecSeed.os_template
    SpecSeed.dns_resolver
    SpecSeed.network_v4
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def json_post(path, payload = {})
    post path, JSON.dump(payload), {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def json_put(path, payload)
    put path, JSON.dump(payload), {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def json_delete(path)
    delete path, {}, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def response_message
    json['message'] || json.dig('response', 'message') || json['error']
  end

  def action_state_id
    json.dig('response', '_meta', 'action_state_id') || json.dig('_meta', 'action_state_id')
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def expect_lifecycle_denied
    expect_status(200)
    expect(json['status']).to be(false)
    expect(response_message).to include('Access forbidden')
    expect(action_state_id).to be_nil
  end

  def set_lifecycle_state!(record, state)
    record.record_object_state_change(
      state,
      reason: 'spec lifecycle restriction',
      user: SpecSeed.admin
    )
    record.reload
  end

  def suspend_user!(user = SpecSeed.user)
    set_lifecycle_state!(user, :suspended)
    user.update!(lockout: false, password_reset: false)
    mark_user_paid_until!(user)
    user.reload
  end

  def primary_pool
    SpecSeed.pool.tap do |pool|
      pool.update!(role: Pool.roles[:primary], refquota_check: false)
    end
  end

  def other_primary_pool
    SpecSeed.other_pool.tap do |pool|
      pool.update!(role: Pool.roles[:primary], refquota_check: false)
    end
  end

  def create_dataset!(user: SpecSeed.user, pool: primary_pool, name: nil, parent: nil)
    create_dataset_with_pool!(
      user: user,
      pool: pool,
      name: name || "lifecycle-ds-#{SecureRandom.hex(4)}",
      parent: parent
    )
  end

  def create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: nil)
    pool = node == SpecSeed.other_node ? other_primary_pool : primary_pool
    _dataset, dip = create_dataset!(user: user, pool: pool)

    Vps.create!(
      user: user,
      node: node,
      hostname: hostname || "lifecycle-vps-#{SecureRandom.hex(4)}",
      os_template: SpecSeed.os_template,
      dns_resolver: SpecSeed.dns_resolver,
      dataset_in_pool: dip,
      object_state: :active
    )
  end

  def create_public_key!(user = SpecSeed.user)
    UserPublicKey.create!(
      user: user,
      label: "lifecycle-key-#{SecureRandom.hex(3)}",
      key: 'ssh-ed25519 aGVsbG8= lifecycle@test',
      auto_add: false
    )
  end

  def create_user_data!(user = SpecSeed.user)
    VpsUserData.create!(
      user: user,
      label: "lifecycle-data-#{SecureRandom.hex(3)}",
      format: 'script',
      content: "#!/bin/sh\necho lifecycle\n"
    )
  end

  def create_mount!(vps:, dip:)
    Mount.create!(
      vps: vps,
      dataset_in_pool: dip,
      dst: "/mnt/lifecycle-#{SecureRandom.hex(3)}",
      mount_opts: '--bind',
      umount_opts: '-f',
      mount_type: 'bind',
      user_editable: false,
      mode: 'rw',
      enabled: true,
      master_enabled: true,
      on_start_fail: :mount_later,
      object_state: :active,
      confirmed: 0
    )
  end

  def seed_features!(vps)
    VpsFeature::FEATURES.each_key do |name|
      feature = VpsFeature.new(vps: vps, name: name.to_s)
      feature.set_to_default
      feature.save!
    end

    vps.reload
  end

  def seed_windows!(vps)
    (0..6).each do |weekday|
      VpsMaintenanceWindow.create!(
        vps: vps,
        weekday: weekday,
        is_open: true,
        opens_at: 0,
        closes_at: 24 * 60
      )
    end
  end

  def create_split_network!
    octet = 20 + SecureRandom.random_number(180)
    network = Network.create!(
      label: "lifecycle-net-#{SecureRandom.hex(4)}",
      ip_version: 4,
      address: "198.51.#{octet}.0",
      prefix: 24,
      role: :public_access,
      managed: true,
      split_access: :no_access,
      split_prefix: 29,
      purpose: :any,
      primary_location: SpecSeed.location
    )

    LocationNetwork.create!(
      location: SpecSeed.location,
      network: network,
      primary: true,
      priority: 10,
      autopick: true,
      userpick: true
    )

    network
  end

  def create_routed_ip_fixture!
    network = create_split_network!
    vps = create_vps!
    netif = NetworkInterface.create!(vps: vps, kind: :veth_routed, name: "eth#{SecureRandom.hex(2)}")
    ip = create_ip_address!(
      network: network,
      location: SpecSeed.location,
      addr: network.address,
      prefix: network.split_prefix,
      size: 8,
      network_interface: netif
    )

    host_addr = "#{network.address.split('.')[0..2].join('.')}.2"
    [vps, ip, ip.host_ip_addresses.first, host_addr]
  end

  def create_tsig_key!(user = SpecSeed.user)
    DnsTsigKey.create!(
      user: user,
      name: "#{user.id}-lifecycle-#{SecureRandom.hex(4)}",
      algorithm: 'hmac-sha256',
      secret: Base64.strict_encode64(SecureRandom.random_bytes(32))
    )
  end

  def create_backup_dip!(dataset:, node:)
    backup_pool = Pool.new(
      node: node,
      label: "lifecycle-backup-#{SecureRandom.hex(3)}",
      filesystem: "lifecycle_backup_#{SecureRandom.hex(3)}",
      role: :backup,
      is_open: true
    ).tap(&:save!)

    DatasetInPool.create!(
      dataset: dataset,
      pool: backup_pool,
      confirmed: DatasetInPool.confirmed(:confirmed)
    )
  end

  describe 'VPS owner operations' do
    it 'blocks suspended users from queuing VPS access/control mutations' do
      vps = create_vps!
      key = create_public_key!
      suspend_user!

      as(SpecSeed.user) { json_post vpath("/vpses/#{vps.id}/passwd"), vps: { type: 'simple' } }
      expect_lifecycle_denied

      as(SpecSeed.user) { json_post vpath("/vpses/#{vps.id}/reinstall"), vps: {} }
      expect_lifecycle_denied

      as(SpecSeed.user) do
        json_post vpath("/vpses/#{vps.id}/deploy_public_key"), vps: { public_key: key.id }
      end
      expect_lifecycle_denied
    end

    it 'blocks active users from cloning, deleting, or swapping suspended VPSes' do
      suspended_vps = create_vps!(hostname: 'lifecycle-suspended-source')
      peer_vps = create_vps!(node: SpecSeed.other_node, hostname: 'lifecycle-swap-peer')
      set_lifecycle_state!(suspended_vps, :suspended)

      as(SpecSeed.user) { json_post vpath("/vpses/#{suspended_vps.id}/clone"), vps: {} }
      expect_lifecycle_denied

      as(SpecSeed.user) { json_delete vpath("/vpses/#{suspended_vps.id}") }
      expect_lifecycle_denied

      as(SpecSeed.user) do
        json_post vpath("/vpses/#{suspended_vps.id}/swap_with"), vps: { vps: peer_vps.id }
      end
      expect_lifecycle_denied
    end
  end

  describe 'VPS nested mutations' do
    it 'blocks suspended users from changing features, mounts, and maintenance windows' do
      vps = create_vps!
      seed_features!(vps)
      seed_windows!(vps)
      child_dataset, child_dip = create_dataset!(
        user: SpecSeed.user,
        pool: vps.dataset_in_pool.pool,
        parent: vps.dataset_in_pool.dataset
      )
      mount = create_mount!(vps: vps, dip: child_dip)
      feature = vps.vps_features.find_by!(name: 'tun')
      suspend_user!

      as(SpecSeed.user) do
        json_put vpath("/vpses/#{vps.id}/features/#{feature.id}"), feature: { enabled: !feature.enabled }
      end
      expect_lifecycle_denied

      as(SpecSeed.user) do
        json_post vpath("/vpses/#{vps.id}/features/update_all"), feature: { tun: false }
      end
      expect_lifecycle_denied

      as(SpecSeed.user) do
        json_post vpath("/vpses/#{vps.id}/mounts"), mount: {
          dataset: child_dataset.id,
          mountpoint: '/mnt/new'
        }
      end
      expect_lifecycle_denied

      as(SpecSeed.user) do
        json_put vpath("/vpses/#{vps.id}/mounts/#{mount.id}"), mount: { enabled: false }
      end
      expect_lifecycle_denied

      as(SpecSeed.user) { json_delete vpath("/vpses/#{vps.id}/mounts/#{mount.id}") }
      expect_lifecycle_denied

      as(SpecSeed.user) do
        json_put vpath("/vpses/#{vps.id}/maintenance_windows/1"), maintenance_window: { is_open: false }
      end
      expect_lifecycle_denied

      as(SpecSeed.user) do
        json_put vpath("/vpses/#{vps.id}/maintenance_windows"), maintenance_window: { is_open: false }
      end
      expect_lifecycle_denied
    end

    it 'blocks suspended users from creating, showing, deleting, or using console tokens' do
      vps = create_vps!
      token = VpsConsole.create_for!(vps, SpecSeed.user)
      suspend_user!

      as(SpecSeed.user) { json_post vpath("/vpses/#{vps.id}/console_token"), {} }
      expect_lifecycle_denied

      as(SpecSeed.user) { json_get vpath("/vpses/#{vps.id}/console_token") }
      expect_lifecycle_denied

      as(SpecSeed.user) { json_delete vpath("/vpses/#{vps.id}/console_token") }
      expect_lifecycle_denied

      console_handler = VpsAdmin::Supervisor::Console::Rpc::Handler.new
      node_handler = VpsAdmin::Supervisor::Node::Rpc::Handler.new(vps.node)

      expect(console_handler.get_session_node(vps.id, token.token)).to be_nil
      expect(node_handler.authenticate_console_session(token.token)).to be_nil
    end
  end

  describe 'Dataset and snapshot mutations' do
    it 'blocks suspended users from mutating datasets' do
      root, = create_dataset!
      suspend_user!

      as(SpecSeed.user) do
        json_post vpath('/datasets'), dataset: { dataset: root.id, name: 'child' }
      end
      expect_lifecycle_denied

      as(SpecSeed.user) { json_put vpath("/datasets/#{root.id}"), dataset: { atime: true } }
      expect_lifecycle_denied

      as(SpecSeed.user) do
        json_post vpath("/datasets/#{root.id}/inherit"), dataset: { property: 'atime' }
      end
      expect_lifecycle_denied

      as(SpecSeed.user) { json_delete vpath("/datasets/#{root.id}") }
      expect_lifecycle_denied
    end

    it 'blocks suspended users from creating, deleting, or rolling back snapshots' do
      dataset, dip = create_dataset!
      snapshot, = create_snapshot!(dataset: dataset, dip: dip)
      older_snapshot, = create_snapshot!(dataset: dataset, dip: dip)
      suspend_user!

      as(SpecSeed.user) do
        json_post vpath("/datasets/#{dataset.id}/snapshots"), snapshot: { label: 'blocked' }
      end
      expect_lifecycle_denied

      as(SpecSeed.user) { json_delete vpath("/datasets/#{dataset.id}/snapshots/#{snapshot.id}") }
      expect_lifecycle_denied

      as(SpecSeed.user) do
        json_post vpath("/datasets/#{dataset.id}/snapshots/#{older_snapshot.id}/rollback"), {}
      end
      expect_lifecycle_denied
    end

    it 'blocks suspended users from changing dataset plans' do
      dataset, dip = create_dataset!
      create_backup_dip!(dataset: dataset, node: dip.pool.node)
      _plan, env_plan = create_daily_backup_env_plan!(environment: SpecSeed.environment)
      existing_plan = dip.add_plan(env_plan)
      suspend_user!

      as(SpecSeed.user) do
        json_post vpath("/datasets/#{dataset.id}/plans"), plan: { environment_dataset_plan: env_plan.id }
      end
      expect_lifecycle_denied

      as(SpecSeed.user) { json_delete vpath("/datasets/#{dataset.id}/plans/#{existing_plan.id}") }
      expect_lifecycle_denied
    end

    it 'blocks active users from exporting deleted datasets or mutating deleted exports' do
      dataset, dip = create_dataset!
      export, = create_export_for_dataset!(dataset_in_pool: dip)
      ip = create_vps_ip_address!(user: SpecSeed.user, pool: dip.pool)
      export_host = ExportHost.create!(
        export: export,
        ip_address: ip,
        rw: true,
        sync: true,
        subtree_check: false,
        root_squash: false
      )

      set_lifecycle_state!(dataset, :deleted)
      as(SpecSeed.user) { json_post vpath('/exports'), export: { dataset: dataset.id } }
      expect_lifecycle_denied

      set_lifecycle_state!(export, :deleted)

      as(SpecSeed.user) { json_put vpath("/exports/#{export.id}"), export: { enabled: false } }
      expect_lifecycle_denied

      as(SpecSeed.user) { json_delete vpath("/exports/#{export.id}") }
      expect_lifecycle_denied

      as(SpecSeed.user) do
        json_post vpath("/exports/#{export.id}/hosts"), host: { ip_address: ip.id }
      end
      expect_lifecycle_denied

      as(SpecSeed.user) do
        json_put vpath("/exports/#{export.id}/hosts/#{export_host.id}"), host: { rw: false }
      end
      expect_lifecycle_denied

      as(SpecSeed.user) { json_delete vpath("/exports/#{export.id}/hosts/#{export_host.id}") }
      expect_lifecycle_denied
    end
  end

  describe 'User-owned control plane records' do
    it 'blocks suspended users from mutating SSH keys and mail recipients' do
      key = create_public_key!
      role = 'account'
      template = MailTemplate.first || raise('missing mail template fixture')
      suspend_user!

      as(SpecSeed.user) do
        json_post vpath("/users/#{SpecSeed.user.id}/public_keys"), public_key: {
          label: 'blocked',
          key: 'ssh-ed25519 aGVsbG8= blocked@test',
          auto_add: true
        }
      end
      expect_lifecycle_denied

      as(SpecSeed.user) do
        json_put vpath("/users/#{SpecSeed.user.id}/public_keys/#{key.id}"), public_key: {
          label: 'blocked update'
        }
      end
      expect_lifecycle_denied

      as(SpecSeed.user) { json_delete vpath("/users/#{SpecSeed.user.id}/public_keys/#{key.id}") }
      expect_lifecycle_denied

      as(SpecSeed.user) do
        json_put vpath("/users/#{SpecSeed.user.id}/mail_role_recipients/#{role}"), mail_role_recipient: {
          to: 'blocked@example.test'
        }
      end
      expect_lifecycle_denied

      as(SpecSeed.user) do
        json_put vpath("/users/#{SpecSeed.user.id}/mail_template_recipients/#{template.name}"),
                 mail_template_recipient: {
                   to: 'blocked@example.test',
                   enabled: true
                 }
      end
      expect_lifecycle_denied
    end

    it 'blocks suspended users from reading or managing DNS TSIG secrets' do
      key = create_tsig_key!
      suspend_user!

      as(SpecSeed.user) { json_get vpath('/dns_tsig_keys') }
      expect_lifecycle_denied

      as(SpecSeed.user) { json_get vpath("/dns_tsig_keys/#{key.id}") }
      expect_lifecycle_denied

      as(SpecSeed.user) { json_post vpath('/dns_tsig_keys'), dns_tsig_key: { name: 'blocked' } }
      expect_lifecycle_denied

      as(SpecSeed.user) { json_delete vpath("/dns_tsig_keys/#{key.id}") }
      expect_lifecycle_denied
    end

    it 'blocks suspended users from deleting snapshot downloads' do
      dataset, dip = create_dataset!
      snapshot, = create_snapshot!(dataset: dataset, dip: dip)
      download = SnapshotDownload.create!(
        user: SpecSeed.user,
        snapshot: snapshot,
        pool: dip.pool,
        secret_key: SecureRandom.hex(16),
        file_name: 'lifecycle.tar.gz',
        confirmed: SnapshotDownload.confirmed(:confirmed),
        format: :archive,
        object_state: :active,
        expiration_date: Time.now + 7.days
      )
      suspend_user!

      as(SpecSeed.user) { json_delete vpath("/snapshot_downloads/#{download.id}") }
      expect_lifecycle_denied
    end

    it 'blocks suspended users from managing namespace maps and entries' do
      user_namespace = UserNamespace.create!(
        user: SpecSeed.user,
        block_count: 0,
        offset: 100_000,
        size: 1_000
      )
      map = UserNamespaceMap.create_direct!(user_namespace, 'lifecycle map')
      entry = UserNamespaceMapEntry.create!(
        user_namespace_map: map,
        kind: :uid,
        vps_id: 0,
        ns_id: 0,
        count: 1
      )
      suspend_user!

      as(SpecSeed.user) do
        json_post vpath('/user_namespace_maps'), user_namespace_map: {
          user_namespace: user_namespace.id,
          label: 'blocked map'
        }
      end
      expect_lifecycle_denied

      as(SpecSeed.user) do
        json_put vpath("/user_namespace_maps/#{map.id}"), user_namespace_map: {
          user_namespace: user_namespace.id,
          label: 'blocked rename'
        }
      end
      expect_lifecycle_denied

      as(SpecSeed.user) do
        json_post vpath("/user_namespace_maps/#{map.id}/entries"), entry: {
          kind: 'uid',
          vps_id: 0,
          ns_id: 1,
          count: 1
        }
      end
      expect_lifecycle_denied

      as(SpecSeed.user) do
        json_put vpath("/user_namespace_maps/#{map.id}/entries/#{entry.id}"), entry: {
          ns_id: 2
        }
      end
      expect_lifecycle_denied

      as(SpecSeed.user) { json_delete vpath("/user_namespace_maps/#{map.id}/entries/#{entry.id}") }
      expect_lifecycle_denied

      as(SpecSeed.user) { json_delete vpath("/user_namespace_maps/#{map.id}") }
      expect_lifecycle_denied
    end
  end

  describe 'Operational per-VPS records' do
    it 'blocks suspended users from creating, updating, or deleting host IP addresses' do
      _vps, ip, host, host_addr = create_routed_ip_fixture!
      suspend_user!

      as(SpecSeed.user) do
        json_post vpath('/host_ip_addresses'), host_ip_address: {
          ip_address: ip.id,
          addr: host_addr
        }
      end
      expect_lifecycle_denied

      as(SpecSeed.user) do
        json_put vpath("/host_ip_addresses/#{host.id}"), host_ip_address: {
          reverse_record_value: 'ptr.example.test'
        }
      end
      expect_lifecycle_denied

      host.update!(user_created: true)
      as(SpecSeed.user) { json_delete vpath("/host_ip_addresses/#{host.id}") }
      expect_lifecycle_denied
    end

    it 'blocks suspended users from managing OOM report rules' do
      vps = create_vps!
      rule = OomReportRule.create!(
        vps: vps,
        action: :notify,
        cgroup_pattern: 'lifecycle/rule',
        hit_count: 0
      )
      suspend_user!

      as(SpecSeed.user) do
        json_post vpath('/oom_report_rules'), oom_report_rule: {
          vps: vps.id,
          action: 'notify',
          cgroup_pattern: 'blocked/rule'
        }
      end
      expect_lifecycle_denied

      as(SpecSeed.user) do
        json_put vpath("/oom_report_rules/#{rule.id}"), oom_report_rule: {
          action: 'ignore'
        }
      end
      expect_lifecycle_denied

      as(SpecSeed.user) { json_delete vpath("/oom_report_rules/#{rule.id}") }
      expect_lifecycle_denied
    end

    it 'blocks suspended users and suspended VPSes from user-data mutations and deploys' do
      vps = create_vps!
      data = create_user_data!
      suspended_vps = create_vps!(hostname: 'lifecycle-user-data-suspended-vps')
      set_lifecycle_state!(suspended_vps, :suspended)

      as(SpecSeed.user) do
        json_post vpath("/vps_user_data/#{data.id}/deploy"), vps_user_data: { vps: suspended_vps.id }
      end
      expect_lifecycle_denied

      suspend_user!

      as(SpecSeed.user) do
        json_post vpath('/vps_user_data'), vps_user_data: {
          label: 'blocked data',
          format: 'script',
          content: "#!/bin/sh\necho blocked\n"
        }
      end
      expect_lifecycle_denied

      as(SpecSeed.user) do
        json_put vpath("/vps_user_data/#{data.id}"), vps_user_data: {
          label: 'blocked update'
        }
      end
      expect_lifecycle_denied

      as(SpecSeed.user) do
        json_post vpath("/vps_user_data/#{data.id}/deploy"), vps_user_data: { vps: vps.id }
      end
      expect_lifecycle_denied

      as(SpecSeed.user) { json_delete vpath("/vps_user_data/#{data.id}") }
      expect_lifecycle_denied
    end
  end
end
