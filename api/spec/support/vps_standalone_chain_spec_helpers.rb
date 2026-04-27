# frozen_string_literal: true

require 'securerandom'
module VpsStandaloneChainSpecHelpers
  def ensure_available_node_status!(node)
    node.update!(
      active: true,
      maintenance_lock: MaintenanceLock.maintain_lock(:no),
      maintenance_lock_reason: nil
    )

    NodeCurrentStatus.find_or_create_by!(node: node) do |status|
      status.vpsadmin_version = 'spec'
      status.kernel = 'spec'
      status.update_count = 1
      status.cgroup_version = :cgroup_v2
      status.pool_state = :online
      status.pool_scan = :none
      status.pool_checked_at = Time.now.utc
      status.created_at = Time.now.utc
      status.updated_at = Time.now.utc
    end
  end

  def build_standalone_vps_fixture(user: SpecSeed.user, node: SpecSeed.node, hostname: nil,
                                   dns_resolver: SpecSeed.dns_resolver, diskspace: 10_240,
                                   dataset_properties: nil)
    pool = create_pool!(node: node, role: :hypervisor, refquota_check: true)
    seed_pool_dataset_properties!(pool)
    ensure_numeric_resources!(user: user, environment: node.location.environment)
    ensure_available_node_status!(node)

    dataset, dataset_in_pool = create_dataset_with_pool!(
      user: user,
      pool: pool,
      name: hostname || "standalone-#{SecureRandom.hex(4)}",
      properties: dataset_properties || { refquota: diskspace }
    )

    allocate_dip_diskspace!(dataset_in_pool, user: user, value: diskspace)

    vps = create_vps_for_dataset!(
      user: user,
      node: node,
      dataset_in_pool: dataset_in_pool,
      hostname: hostname || "standalone-#{SecureRandom.hex(4)}",
      dns_resolver: dns_resolver
    )
    allocate_vps_resources!(vps, user: user)

    {
      pool: pool,
      dataset: dataset,
      dataset_in_pool: dataset_in_pool,
      vps: vps
    }
  end

  def create_vps_subdataset!(user:, pool:, parent:, name: nil, properties: { refquota: 2_048 })
    create_dataset_with_pool!(
      user: user,
      pool: pool,
      parent: parent,
      name: name || "subdataset-#{SecureRandom.hex(4)}",
      properties: properties
    )
  end

  def create_mount_record!(vps:, dataset_in_pool:, dst:, mode: 'rw', enabled: true,
                           master_enabled: true, on_start_fail: :mount_later)
    Mount.create!(
      vps: vps,
      dst: dst,
      mount_opts: '--bind',
      umount_opts: '-f',
      mount_type: 'bind',
      user_editable: false,
      dataset_in_pool: dataset_in_pool,
      mode: mode,
      enabled: enabled,
      master_enabled: master_enabled,
      on_start_fail: on_start_fail,
      object_state: :active,
      confirmed: Mount.confirmed(:confirmed)
    )
  end

  def create_snapshot_mount_record!(vps:, snapshot_in_pool:, dst: '/mnt/snapshot')
    Mount.create!(
      vps: vps,
      dst: dst,
      mount_opts: '-o ro',
      umount_opts: '-f',
      mount_type: 'bind',
      user_editable: false,
      snapshot_in_pool: snapshot_in_pool,
      mode: 'ro',
      enabled: true,
      master_enabled: true,
      on_start_fail: :mount_later,
      object_state: :active,
      confirmed: Mount.confirmed(:confirmed)
    )
  end

  def set_refquota!(dataset_in_pool, value)
    dataset_in_pool.dataset_properties.find_by!(name: 'refquota').update!(
      value: value,
      inherited: false
    )
  end

  def build_dataset_expansion_fixture(user: SpecSeed.user, original_refquota: 10_240,
                                      added_space: 4_096, enable_notifications: true)
    fixture = build_standalone_vps_fixture(
      user: user,
      diskspace: original_refquota,
      hostname: "expand-#{SecureRandom.hex(4)}"
    )

    fixture.merge(
      expansion: DatasetExpansion.new(
        vps: fixture.fetch(:vps),
        dataset: fixture.fetch(:dataset),
        added_space: added_space,
        enable_notifications: enable_notifications,
        enable_shrink: true,
        stop_vps: false,
        max_over_refquota_seconds: 3_600
      )
    )
  end

  def build_active_dataset_expansion_fixture(user: SpecSeed.user, original_refquota: 10_240,
                                             added_space: 2_048, enable_notifications: true)
    current_refquota = original_refquota + added_space
    fixture = build_standalone_vps_fixture(
      user: user,
      diskspace: original_refquota,
      hostname: "expanded-#{SecureRandom.hex(4)}"
    )
    dip = fixture.fetch(:dataset_in_pool)

    set_refquota!(dip, current_refquota)

    expansion = DatasetExpansion.create_for_expanded!(
      dip,
      vps: fixture.fetch(:vps),
      dataset: fixture.fetch(:dataset),
      state: :active,
      original_refquota: original_refquota,
      added_space: added_space,
      enable_notifications: enable_notifications,
      enable_shrink: true,
      stop_vps: false,
      max_over_refquota_seconds: 3_600
    )

    fixture.merge(expansion: expansion, current_refquota: current_refquota)
  end

  def build_mail_log_double
    mail_log = MailLog.new(
      to: 'spec@example.test',
      cc: nil,
      bcc: nil,
      from: 'spec@example.test',
      reply_to: nil,
      return_path: nil,
      message_id: nil,
      in_reply_to: nil,
      references: nil,
      subject: 'spec',
      text_plain: 'spec',
      text_html: nil
    )

    allow(mail_log).to receive(:update!).and_return(true)
    mail_log
  end
end

RSpec.configure do |config|
  config.include VpsStandaloneChainSpecHelpers
end
