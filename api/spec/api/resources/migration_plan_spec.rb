# frozen_string_literal: true

require 'securerandom'

RSpec.describe 'VpsAdmin::API::Resources::MigrationPlan' do
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
  end

  def index_path
    vpath('/migration_plans')
  end

  def show_path(id)
    vpath("/migration_plans/#{id}")
  end

  def create_path
    index_path
  end

  def start_path(id)
    vpath("/migration_plans/#{id}/start")
  end

  def cancel_path(id)
    vpath("/migration_plans/#{id}/cancel")
  end

  def delete_path(id)
    show_path(id)
  end

  def vps_migrations_path(plan_id)
    vpath("/migration_plans/#{plan_id}/vps_migrations")
  end

  def vps_migration_path(plan_id, migration_id)
    vpath("/migration_plans/#{plan_id}/vps_migrations/#{migration_id}")
  end

  def json_get(path, params = nil)
    get path, params, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def json_post(path, payload)
    post path, JSON.dump(payload), {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def json_delete(path)
    delete path, {}, {
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => StringIO.new('{}')
    }
  end

  def migration_plans
    json.dig('response', 'migration_plans') || []
  end

  def migration_plan_obj
    json.dig('response', 'migration_plan') || json['response']
  end

  def vps_migrations
    json.dig('response', 'vps_migrations') || []
  end

  def vps_migration_obj
    json.dig('response', 'vps_migration') || json['response']
  end

  def response_errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def response_message
    json['message'] || json.dig('response', 'message') || json['error']
  end

  def resource_id(value)
    return value['id'] if value.is_a?(Hash)

    value
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  def create_plan!(user:, state:, **attrs)
    MigrationPlan.create!({
      user: user,
      state: state,
      stop_on_error: true,
      send_mail: true,
      concurrency: 10
    }.merge(attrs))
  end

  def create_dataset_in_pool!(user:, pool:)
    dataset = Dataset.create!(
      name: "spec-#{SecureRandom.hex(4)}",
      user: user,
      user_editable: true,
      user_create: true,
      user_destroy: true,
      object_state: :active
    )

    DatasetInPool.create!(dataset: dataset, pool: pool)
  end

  def create_vps!(user:, node:, hostname:)
    pool = node == SpecSeed.other_node ? SpecSeed.other_pool : SpecSeed.pool
    dip = create_dataset_in_pool!(user: user, pool: pool)

    Vps.create!(
      user: user,
      node: node,
      hostname: hostname,
      os_template: SpecSeed.os_template,
      dns_resolver: SpecSeed.dns_resolver,
      dataset_in_pool: dip,
      object_state: :active
    )
  end

  def create_chain!(name: 'spec_chain', type: 'TransactionChain')
    TransactionChain.create!(
      name: name,
      type: type,
      state: :queued,
      size: 1,
      progress: 0,
      user: User.current || SpecSeed.admin,
      user_session: UserSession.current || UserSession.order(:id).last,
      concern_type: :chain_affect
    )
  end

  def create_index_plans
    {
      plan_staged_admin: create_plan!(user: SpecSeed.admin, state: :staged),
      plan_running_admin: create_plan!(user: SpecSeed.admin, state: :running),
      plan_done_admin: create_plan!(user: SpecSeed.admin, state: :done),
      plan_staged_other: create_plan!(user: SpecSeed.other_user, state: :staged)
    }
  end

  def create_start_plan
    plan = create_plan!(user: SpecSeed.admin, state: :staged, concurrency: 1, send_mail: true)
    vps_a = create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'spec-start-a')
    vps_b = create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'spec-start-b')

    migration_a = plan.vps_migrations.create!(
      vps: vps_a,
      src_node: vps_a.node,
      dst_node: SpecSeed.other_node
    )
    migration_b = plan.vps_migrations.create!(
      vps: vps_b,
      src_node: vps_b.node,
      dst_node: SpecSeed.other_node
    )

    {
      plan: plan,
      vps_a: vps_a,
      vps_b: vps_b,
      migration_a: migration_a,
      migration_b: migration_b
    }
  end

  def create_cancel_plan
    plan = create_plan!(user: SpecSeed.admin, state: :running)
    vps_a = create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'spec-cancel-a')
    vps_b = create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'spec-cancel-b')

    queued = plan.vps_migrations.create!(
      vps: vps_a,
      src_node: vps_a.node,
      dst_node: SpecSeed.other_node,
      state: :queued
    )
    running = plan.vps_migrations.create!(
      vps: vps_b,
      src_node: vps_b.node,
      dst_node: SpecSeed.other_node,
      state: :running
    )

    {
      plan: plan,
      queued: queued,
      running: running
    }
  end

  def create_vps_migration_fixtures
    plan_a = create_plan!(user: SpecSeed.admin, state: :staged)
    plan_b = create_plan!(user: SpecSeed.admin, state: :staged)
    vps_a = create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'spec-vps-a')
    vps_b = create_vps!(user: SpecSeed.user, node: SpecSeed.other_node, hostname: 'spec-vps-b')
    vps_c = create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'spec-vps-c')

    m1 = plan_a.vps_migrations.create!(
      vps: vps_a,
      src_node: vps_a.node,
      dst_node: SpecSeed.other_node
    )
    m2 = plan_a.vps_migrations.create!(
      vps: vps_b,
      src_node: vps_b.node,
      dst_node: SpecSeed.node
    )
    m3 = plan_b.vps_migrations.create!(
      vps: vps_c,
      src_node: vps_c.node,
      dst_node: SpecSeed.other_node
    )

    {
      plan_a: plan_a,
      plan_b: plan_b,
      vps_a: vps_a,
      vps_b: vps_b,
      vps_c: vps_c,
      m1: m1,
      m2: m2,
      m3: m3
    }
  end

  describe 'MigrationPlan' do
    describe 'Index' do
      it 'rejects unauthenticated access' do
        json_get index_path

        expect_status(401)
        expect(json['status']).to be(false)
      end

      it 'forbids non-admin access' do
        as(SpecSeed.user) { json_get index_path }

        expect_status(403)
        expect(json['status']).to be(false)
      end

      it 'lists plans for admins' do
        plans = create_index_plans

        as(SpecSeed.admin) { json_get index_path }

        expect_status(200)
        expect(json['status']).to be(true)
        ids = migration_plans.map { |row| row['id'] }
        expect(ids).to include(
          plans[:plan_staged_admin].id,
          plans[:plan_running_admin].id,
          plans[:plan_done_admin].id,
          plans[:plan_staged_other].id
        )
      end

      it 'filters by state' do
        plans = create_index_plans

        as(SpecSeed.admin) { json_get index_path, migration_plan: { state: 'staged' } }

        expect_status(200)
        expect(json['status']).to be(true)
        ids = migration_plans.map { |row| row['id'] }
        expect(ids).to include(plans[:plan_staged_admin].id, plans[:plan_staged_other].id)
        expect(ids).not_to include(plans[:plan_running_admin].id, plans[:plan_done_admin].id)
      end

      it 'filters by user' do
        plans = create_index_plans

        as(SpecSeed.admin) { json_get index_path, migration_plan: { user: SpecSeed.other_user.id } }

        expect_status(200)
        expect(json['status']).to be(true)
        ids = migration_plans.map { |row| row['id'] }
        expect(ids).to include(plans[:plan_staged_other].id)
        expect(ids).not_to include(plans[:plan_staged_admin].id, plans[:plan_running_admin].id)
      end

      it 'returns total_count meta when requested' do
        create_index_plans

        as(SpecSeed.admin) { json_get index_path, _meta: { count: true } }

        expect_status(200)
        expect(json.dig('response', '_meta', 'total_count')).to eq(MigrationPlan.count)
      end

      it 'supports limit pagination' do
        create_index_plans

        as(SpecSeed.admin) { json_get index_path, migration_plan: { limit: 1 } }

        expect_status(200)
        expect(migration_plans.length).to eq(1)
      end
    end

    describe 'Show' do
      it 'rejects unauthenticated access' do
        plan = create_plan!(user: SpecSeed.admin, state: :staged)

        json_get show_path(plan.id)

        expect_status(401)
        expect(json['status']).to be(false)
      end

      it 'forbids non-admin access' do
        plan = create_plan!(user: SpecSeed.admin, state: :staged)

        as(SpecSeed.user) { json_get show_path(plan.id) }

        expect_status(403)
        expect(json['status']).to be(false)
      end

      it 'shows plan details for admins' do
        plan = create_plan!(user: SpecSeed.admin, state: :staged)

        as(SpecSeed.admin) { json_get show_path(plan.id) }

        expect_status(200)
        expect(json['status']).to be(true)
        expect(migration_plan_obj['id']).to eq(plan.id)
        expect(migration_plan_obj['state']).to eq('staged')
        expect(resource_id(migration_plan_obj['user'])).to eq(plan.user_id)
      end

      it 'returns 404 for unknown plan' do
        missing = MigrationPlan.maximum(:id).to_i + 100

        as(SpecSeed.admin) { json_get show_path(missing) }

        expect_status(404)
        expect(json['status']).to be(false)
      end
    end

    describe 'Create' do
      it 'rejects unauthenticated access' do
        json_post create_path, migration_plan: {}

        expect_status(401)
        expect(json['status']).to be(false)
      end

      it 'forbids non-admin access' do
        as(SpecSeed.user) { json_post create_path, migration_plan: {} }

        expect_status(403)
        expect(json['status']).to be(false)
      end

      it 'creates a plan with defaults' do
        as(SpecSeed.admin) { json_post create_path, migration_plan: {} }

        expect_status(200)
        expect(json['status']).to be(true)

        plan = MigrationPlan.find(migration_plan_obj['id'])
        expect(plan.state).to eq('staged')
        expect(plan.stop_on_error).to be(true)
        expect(plan.send_mail).to be(true)
        expect(plan.concurrency).to eq(10)
        expect(plan.user_id).to eq(SpecSeed.admin.id)
      end

      it 'creates a plan with overrides' do
        as(SpecSeed.admin) do
          json_post create_path, migration_plan: {
            stop_on_error: false,
            send_mail: false,
            concurrency: 2,
            reason: 'spec reason'
          }
        end

        expect_status(200)
        expect(json['status']).to be(true)

        plan = MigrationPlan.find(migration_plan_obj['id'])
        expect(plan.stop_on_error).to be(false)
        expect(plan.send_mail).to be(false)
        expect(plan.concurrency).to eq(2)
        expect(plan.reason).to eq('spec reason')
      end

      it 'returns validation errors for invalid concurrency' do
        as(SpecSeed.admin) { json_post create_path, migration_plan: { concurrency: 'nope' } }

        expect_status(200)
        expect(json['status']).to be(false)
        expect(response_errors.keys.map(&:to_s)).to include('concurrency')
      end
    end

    describe 'Start' do
      before do
        fake_chain = class_double(TransactionChain)
        allow(fake_chain).to receive(:fire2) do |**_kwargs|
          [create_chain!(name: 'spec_vps_migrate'), nil]
        end

        allow(TransactionChains::Vps::Migrate).to receive(:chain_for).and_return(fake_chain)

        allow(TransactionChains::MigrationPlan::Mail).to receive(:fire) do |_plan|
          [
            create_chain!(
              name: 'spec_migration_plan_mail',
              type: TransactionChains::MigrationPlan::Mail.name
            ),
            nil
          ]
        end
      end

      it 'rejects unauthenticated access' do
        data = create_start_plan

        json_post start_path(data[:plan].id), {}

        expect_status(401)
        expect(json['status']).to be(false)
      end

      it 'forbids non-admin access' do
        data = create_start_plan

        as(SpecSeed.user) { json_post start_path(data[:plan].id), {} }

        expect_status(403)
        expect(json['status']).to be(false)
      end

      it 'starts a staged plan and advances migrations' do
        data = create_start_plan

        as(SpecSeed.admin) { json_post start_path(data[:plan].id), {} }

        expect_status(200)
        expect(json['status']).to be(true)
        expect(TransactionChains::MigrationPlan::Mail).to have_received(:fire).once

        data[:plan].reload
        expect(data[:plan].state).to eq('running')

        data[:migration_a].reload
        data[:migration_b].reload

        running = [data[:migration_a], data[:migration_b]].select { |m| m.state == 'running' }
        queued = [data[:migration_a], data[:migration_b]].select { |m| m.state == 'queued' }

        expect(running.length).to eq(1)
        expect(queued.length).to eq(1)
        expect(running.first.started_at).not_to be_nil
        expect(running.first.transaction_chain_id).not_to be_nil
      end

      it 'rejects start on non-staged plan' do
        plan = create_plan!(user: SpecSeed.admin, state: :running)

        as(SpecSeed.admin) { json_post start_path(plan.id), {} }

        expect_status(200)
        expect(json['status']).to be(false)
        expect(response_message).to eq('This migration plan has already been started')
      end

      it 'returns 404 for missing plan' do
        missing = MigrationPlan.maximum(:id).to_i + 100

        as(SpecSeed.admin) { json_post start_path(missing), {} }

        expect_status(404)
        expect(json['status']).to be(false)
      end
    end

    describe 'Cancel' do
      it 'rejects unauthenticated access' do
        data = create_cancel_plan

        json_post cancel_path(data[:plan].id), {}

        expect_status(401)
        expect(json['status']).to be(false)
      end

      it 'forbids non-admin access' do
        data = create_cancel_plan

        as(SpecSeed.user) { json_post cancel_path(data[:plan].id), {} }

        expect_status(403)
        expect(json['status']).to be(false)
      end

      it 'cancels a running plan and queued migrations' do
        data = create_cancel_plan

        as(SpecSeed.admin) { json_post cancel_path(data[:plan].id), {} }

        expect_status(200)
        expect(json['status']).to be(true)

        data[:plan].reload
        data[:queued].reload
        data[:running].reload

        expect(data[:plan].state).to eq('cancelling')
        expect(data[:queued].state).to eq('cancelled')
        expect(data[:running].state).to eq('running')
      end

      it 'rejects cancel on non-running plan' do
        plan = create_plan!(user: SpecSeed.admin, state: :staged)

        as(SpecSeed.admin) { json_post cancel_path(plan.id), {} }

        expect_status(200)
        expect(json['status']).to be(false)
        expect(response_message).to eq('This migration plan is not running')
      end

      it 'returns 404 for missing plan' do
        missing = MigrationPlan.maximum(:id).to_i + 100

        as(SpecSeed.admin) { json_post cancel_path(missing), {} }

        expect_status(404)
        expect(json['status']).to be(false)
      end
    end

    describe 'Delete' do
      it 'rejects unauthenticated access' do
        plan = create_plan!(user: SpecSeed.admin, state: :staged)

        json_delete delete_path(plan.id)

        expect_status(401)
        expect(json['status']).to be(false)
      end

      it 'forbids non-admin access' do
        plan = create_plan!(user: SpecSeed.admin, state: :staged)

        as(SpecSeed.user) { json_delete delete_path(plan.id) }

        expect_status(403)
        expect(json['status']).to be(false)
      end

      it 'deletes a staged plan' do
        plan = create_plan!(user: SpecSeed.admin, state: :staged)

        as(SpecSeed.admin) { json_delete delete_path(plan.id) }

        expect_status(200)
        expect(json['status']).to be(true)
        expect(MigrationPlan.exists?(plan.id)).to be(false)
      end

      it 'rejects delete on non-staged plan' do
        plan = create_plan!(user: SpecSeed.admin, state: :running)

        as(SpecSeed.admin) { json_delete delete_path(plan.id) }

        expect_status(200)
        expect(json['status']).to be(false)
        expect(response_message).to eq('This migration plan is not in the staging phase anymore')
        expect(MigrationPlan.exists?(plan.id)).to be(true)
      end

      it 'returns 404 for missing plan' do
        missing = MigrationPlan.maximum(:id).to_i + 100

        as(SpecSeed.admin) { json_delete delete_path(missing) }

        expect_status(404)
        expect(json['status']).to be(false)
      end
    end
  end

  describe 'VpsMigration (nested)' do
    describe 'Index' do
      it 'rejects unauthenticated access' do
        data = create_vps_migration_fixtures

        json_get vps_migrations_path(data[:plan_a].id)

        expect_status(401)
        expect(json['status']).to be(false)
      end

      it 'forbids non-admin access' do
        data = create_vps_migration_fixtures

        as(SpecSeed.user) { json_get vps_migrations_path(data[:plan_a].id) }

        expect_status(403)
        expect(json['status']).to be(false)
      end

      it 'lists only migrations for the plan' do
        data = create_vps_migration_fixtures

        as(SpecSeed.admin) { json_get vps_migrations_path(data[:plan_a].id) }

        expect_status(200)
        expect(json['status']).to be(true)
        ids = vps_migrations.map { |row| row['id'] }
        expect(ids).to include(data[:m1].id, data[:m2].id)
        expect(ids).not_to include(data[:m3].id)
      end

      it 'filters by state' do
        data = create_vps_migration_fixtures
        data[:m1].update!(state: :running)

        as(SpecSeed.admin) do
          json_get vps_migrations_path(data[:plan_a].id), vps_migration: { state: 'running' }
        end

        expect_status(200)
        expect(json['status']).to be(true)
        ids = vps_migrations.map { |row| row['id'] }
        expect(ids).to include(data[:m1].id)
        expect(ids).not_to include(data[:m2].id)
      end

      it 'filters by src_node' do
        data = create_vps_migration_fixtures

        as(SpecSeed.admin) do
          json_get vps_migrations_path(data[:plan_a].id), vps_migration: { src_node: SpecSeed.node.id }
        end

        expect_status(200)
        ids = vps_migrations.map { |row| row['id'] }
        expect(ids).to include(data[:m1].id)
        expect(ids).not_to include(data[:m2].id)
      end

      it 'filters by dst_node' do
        data = create_vps_migration_fixtures

        as(SpecSeed.admin) do
          json_get vps_migrations_path(data[:plan_a].id), vps_migration: { dst_node: SpecSeed.node.id }
        end

        expect_status(200)
        ids = vps_migrations.map { |row| row['id'] }
        expect(ids).to include(data[:m2].id)
        expect(ids).not_to include(data[:m1].id)
      end
    end

    describe 'Show' do
      it 'rejects unauthenticated access' do
        data = create_vps_migration_fixtures

        json_get vps_migration_path(data[:plan_a].id, data[:m1].id)

        expect_status(401)
        expect(json['status']).to be(false)
      end

      it 'forbids non-admin access' do
        data = create_vps_migration_fixtures

        as(SpecSeed.user) { json_get vps_migration_path(data[:plan_a].id, data[:m1].id) }

        expect_status(403)
        expect(json['status']).to be(false)
      end

      it 'shows migration details for admins' do
        data = create_vps_migration_fixtures

        as(SpecSeed.admin) { json_get vps_migration_path(data[:plan_a].id, data[:m1].id) }

        expect_status(200)
        expect(json['status']).to be(true)
        expect(resource_id(vps_migration_obj['vps'])).to eq(data[:vps_a].id)
        expect(resource_id(vps_migration_obj['dst_node'])).to eq(SpecSeed.other_node.id)
        expect(resource_id(vps_migration_obj['src_node'])).to eq(data[:vps_a].node_id)
      end

      it 'returns 404 for wrong plan id' do
        data = create_vps_migration_fixtures

        as(SpecSeed.admin) { json_get vps_migration_path(data[:plan_b].id, data[:m1].id) }

        expect_status(404)
        expect(json['status']).to be(false)
      end

      it 'returns 404 for missing migration' do
        data = create_vps_migration_fixtures
        missing = VpsMigration.maximum(:id).to_i + 100

        as(SpecSeed.admin) { json_get vps_migration_path(data[:plan_a].id, missing) }

        expect_status(404)
        expect(json['status']).to be(false)
      end
    end

    describe 'Create' do
      it 'rejects unauthenticated access' do
        data = create_vps_migration_fixtures

        json_post vps_migrations_path(data[:plan_a].id), vps_migration: {
          vps: data[:vps_a].id,
          dst_node: SpecSeed.other_node.id
        }

        expect_status(401)
        expect(json['status']).to be(false)
      end

      it 'forbids non-admin access' do
        data = create_vps_migration_fixtures

        as(SpecSeed.user) do
          json_post vps_migrations_path(data[:plan_a].id), vps_migration: {
            vps: data[:vps_a].id,
            dst_node: SpecSeed.other_node.id
          }
        end

        expect_status(403)
        expect(json['status']).to be(false)
      end

      it 'creates a migration under a staged plan' do
        data = create_vps_migration_fixtures
        vps_new = create_vps!(user: SpecSeed.user, node: SpecSeed.node, hostname: 'spec-vps-new')

        as(SpecSeed.admin) do
          json_post vps_migrations_path(data[:plan_a].id), vps_migration: {
            vps: vps_new.id,
            dst_node: SpecSeed.other_node.id
          }
        end

        expect_status(200)
        expect(json['status']).to be(true)

        created = VpsMigration.order(:id).last
        expect(created.migration_plan_id).to eq(data[:plan_a].id)
        expect(created.vps_id).to eq(vps_new.id)
        expect(created.src_node_id).to eq(vps_new.node_id)
        expect(created.dst_node_id).to eq(SpecSeed.other_node.id)

        expect(resource_id(vps_migration_obj['vps'])).to eq(vps_new.id)
        expect(resource_id(vps_migration_obj['dst_node'])).to eq(SpecSeed.other_node.id)
        expect(resource_id(vps_migration_obj['src_node'])).to eq(vps_new.node_id)
      end

      it 'returns validation errors for missing vps' do
        data = create_vps_migration_fixtures

        as(SpecSeed.admin) do
          json_post vps_migrations_path(data[:plan_a].id), vps_migration: {
            dst_node: SpecSeed.other_node.id
          }
        end

        expect_status(200)
        expect(json['status']).to be(false)
        expect(response_errors.keys.map(&:to_s)).to include('vps')
      end

      it 'returns validation errors for missing dst_node' do
        data = create_vps_migration_fixtures

        as(SpecSeed.admin) do
          json_post vps_migrations_path(data[:plan_a].id), vps_migration: {
            vps: data[:vps_a].id
          }
        end

        expect_status(200)
        expect(json['status']).to be(false)
        expect(response_errors.keys.map(&:to_s)).to include('dst_node')
      end

      it 'rejects create when plan is not staged' do
        data = create_vps_migration_fixtures
        data[:plan_a].update!(state: :running)

        as(SpecSeed.admin) do
          json_post vps_migrations_path(data[:plan_a].id), vps_migration: {
            vps: data[:vps_a].id,
            dst_node: SpecSeed.other_node.id
          }
        end

        expect_status(200)
        expect(json['status']).to be(false)
        expect(response_message).to eq('This migration plans has already been started.')
      end

      it 'returns 404 for missing plan' do
        data = create_vps_migration_fixtures
        missing = MigrationPlan.maximum(:id).to_i + 100

        as(SpecSeed.admin) do
          json_post vps_migrations_path(missing), vps_migration: {
            vps: data[:vps_a].id,
            dst_node: SpecSeed.other_node.id
          }
        end

        expect_status(404)
        expect(json['status']).to be(false)
      end
    end
  end
end
