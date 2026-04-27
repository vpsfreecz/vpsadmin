# frozen_string_literal: true

require 'securerandom'

module MigrationPlanSpecHelpers
  def build_active_chain!(state: :queued, name: 'spec_migration_chain')
    TransactionChain.create!(
      name: name,
      type: 'TransactionChain',
      state: state,
      size: 0,
      progress: 0,
      user: User.current || SpecSeed.admin,
      user_session: UserSession.current,
      urgent_rollback: false
    )
  end

  def create_vps_migration_fixture!(count: 2, users: nil)
    src_node = SpecSeed.node
    dst_node = create_node!(
      location: src_node.location,
      role: :node,
      name: "dst-#{SecureRandom.hex(3)}"
    )

    src_pool = create_pool!(node: src_node, role: :hypervisor)
    src_pool.update!(migration_public_key: 'spec-src-pubkey')
    create_pool!(
      node: dst_node,
      role: :hypervisor,
      filesystem: "spec_hv_dst_#{SecureRandom.hex(4)}"
    )

    vpses = count.times.map do |i|
      user = users ? users.fetch(i) : SpecSeed.user
      dataset, dip = create_dataset_with_pool!(
        user: user,
        pool: src_pool,
        name: "plan-vps-#{i}-#{SecureRandom.hex(3)}"
      )
      create_vps_for_dataset!(user: user, node: src_node, dataset_in_pool: dip)
    end

    { src_node: src_node, dst_node: dst_node, src_pool: src_pool, vpses: vpses }
  end

  def create_migration_plan!(dst_node:, state: :staged, concurrency: 1, stop_on_error: false,
                             send_mail: false)
    MigrationPlan.create!(
      user: SpecSeed.admin,
      node: dst_node,
      concurrency: concurrency,
      stop_on_error: stop_on_error,
      send_mail: send_mail,
      reason: 'spec',
      state: state
    )
  end

  def build_vps_migration!(plan:, vps:, state: :queued, transaction_chain: nil, created_at: nil)
    plan.vps_migrations.create!(
      vps: vps,
      src_node: vps.node,
      dst_node: plan.node,
      state: state,
      outage_window: false,
      cleanup_data: true,
      transaction_chain: transaction_chain,
      created_at: created_at || Time.now
    )
  end

  def build_unsaved_vps_migration(plan:, vps:, state: :queued, transaction_chain: nil)
    plan.vps_migrations.build(
      vps: vps,
      src_node: vps.node,
      dst_node: plan.node,
      state: state,
      outage_window: false,
      cleanup_data: true,
      transaction_chain: transaction_chain
    )
  end

  def create_maintenance_window!(vps:, weekday:, is_open:, opens_at: nil, closes_at: nil,
                                 validate: false)
    window = VpsMaintenanceWindow.new(
      vps: vps,
      weekday: weekday,
      is_open: is_open,
      opens_at: opens_at,
      closes_at: closes_at
    )
    window.save!(validate: validate)
    window
  end

  def seed_weekly_open_time!(vps, except: nil, minutes_per_day: 120)
    (0..6).each do |weekday|
      next if weekday == except

      create_maintenance_window!(
        vps: vps,
        weekday: weekday,
        is_open: true,
        opens_at: 0,
        closes_at: minutes_per_day,
        validate: false
      )
    end
  end
end

RSpec.configure do |config|
  config.include MigrationPlanSpecHelpers
end
