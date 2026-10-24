# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::Supervisor::Node::Rpc::Handler do
  subject(:handler) { described_class.new(node) }

  let(:node) { SpecSeed.node }
  let(:pool) { SpecSeed.pool }

  def create_boot_vps(**attrs)
    _, dip = create_dataset_with_pool!(
      user: SpecSeed.user,
      pool: pool,
      name: "boot-rpc-#{SecureRandom.hex(4)}"
    )

    Vps.create!(
      {
        user: SpecSeed.user,
        node: node,
        hostname: "boot-rpc-#{SecureRandom.hex(4)}",
        os_template: SpecSeed.os_template,
        dns_resolver: SpecSeed.dns_resolver,
        dataset_in_pool: dip,
        user_namespace_map: create_user_namespace_map!(user: SpecSeed.user),
        object_state: :active,
        confirmed: :confirmed,
        autostart_enable: true
      }.merge(attrs)
    )
  end

  def reconcile(*ids)
    handler.reconcile_vps_boot_autostart(ids.sort).fetch(:vpses)
  end

  def disposition(id, value, reason, pool_fs: nil)
    { id:, disposition: value, reason:, pool_fs: }
  end

  def select_queries(&block)
    queries = []
    callback = lambda do |event|
      sql = event.payload.fetch(:sql)
      queries << sql if sql.match?(/\ASELECT\b/i)
    end

    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &block)
    queries
  end

  it 'allowlists both node RPCs' do
    expect(described_class::COMMANDS).to include(
      'list_vps_boot_autostart', 'reconcile_vps_boot_autostart'
    )
  end

  describe '#list_vps_boot_autostart' do
    it 'returns an empty versioned inventory' do
      expect(handler.list_vps_boot_autostart).to eq(schema_version: 1, vpses: [])
    end

    it 'returns all confirmed local active and suspended enabled VPSes by ID' do
      first = create_boot_vps
      suspended = create_boot_vps(object_state: :suspended)
      create_boot_vps(autostart_enable: false)
      create_boot_vps(node: SpecSeed.other_node)
      create_boot_vps(confirmed: :confirm_create)
      create_boot_vps(confirmed: :confirm_destroy)
      create_boot_vps(object_state: :soft_delete)

      # No osctld/status row is needed: missing containers and unimported pools
      # must still enroll, including a VPS currently locked by a transaction.
      first.acquire_lock
      expect(handler.list_vps_boot_autostart).to eq(
        schema_version: 1,
        vpses: [first, suspended].map { |vps| { id: vps.id, pool_fs: pool.filesystem } }
      )
    end

    it 'reads the complete inventory in one statement' do
      create_boot_vps
      expect(select_queries { handler.list_vps_boot_autostart }.size).to eq(1)
    end

    it 'fails the whole inventory when an enabled VPS has no dataset association' do
      create_boot_vps
      create_boot_vps.update_column(:dataset_in_pool_id, nil)

      expect { handler.list_vps_boot_autostart }.to raise_error(RuntimeError, 'inventory_invalid')
    end

    it 'fails when the associated pool is missing' do
      vps = create_boot_vps
      vps.dataset_in_pool.update_column(:pool_id, Pool.maximum(:id) + 1)

      expect { handler.list_vps_boot_autostart }.to raise_error(RuntimeError, 'inventory_invalid')
    end

    it 'fails when the associated pool belongs to another node' do
      vps = create_boot_vps
      vps.dataset_in_pool.update_column(:pool_id, SpecSeed.other_pool.id)

      expect { handler.list_vps_boot_autostart }.to raise_error(RuntimeError, 'inventory_invalid')
    end

    ['', '/tank/vps', 'tank//vps', 'tank/vps/', 'tank vps', 'tank/.', 'tank/../vps'].each do |filesystem|
      it "fails for invalid pool filesystem #{filesystem.inspect}" do
        create_boot_vps
        Pool.where(id: pool.id).update_all(filesystem: filesystem)

        expect { handler.list_vps_boot_autostart }.to raise_error(RuntimeError, 'inventory_invalid')
      end
    end
  end

  JSON.parse(File.read(File.expand_path('../../../../tests/fixtures/boot-autostart-pool-filesystems.json', __dir__))).each do |fixture|
    it "uses the shared filesystem contract for inventory and reconciliation of #{fixture.fetch('filesystem').inspect}" do
      vps = create_boot_vps
      filesystem = fixture.fetch('filesystem')
      Pool.where(id: pool.id).update_all(filesystem:)
      if fixture.fetch('valid')
        expect(handler.list_vps_boot_autostart).to eq(
          schema_version: 1, vpses: [{ id: vps.id, pool_fs: filesystem }]
        )
        expect(reconcile(vps.id)).to eq([disposition(vps.id, 'retain', 'expected', pool_fs: filesystem)])
      else
        expect { handler.list_vps_boot_autostart }.to raise_error(RuntimeError, 'inventory_invalid')
        expect(reconcile(vps.id)).to eq([disposition(vps.id, 'unknown', 'inventory_invalid')])
      end
    end
  end

  describe '#reconcile_vps_boot_autostart' do
    it 'retains active and suspended expected VPSes with their current pools' do
      active = create_boot_vps
      suspended = create_boot_vps(object_state: :suspended)

      expect(reconcile(active.id, suspended.id)).to eq(
        [active, suspended].map do |vps|
          disposition(vps.id, 'retain', 'expected', pool_fs: pool.filesystem)
        end
      )
    end

    it 'retains any resource lock, including locks on missing or foreign rows' do
      foreign = create_boot_vps(node: SpecSeed.other_node, autostart_enable: false)
      foreign.acquire_lock
      missing_id = Vps.unscoped.maximum(:id) + 1
      ResourceLock.create!(resource: 'Vps', row_id: missing_id)

      expect(reconcile(foreign.id, missing_id)).to eq(
        [foreign.id, missing_id].map { |id| disposition(id, 'retain', 'resource_locked') }
      )
    end

    it 'retains locks belonging to fatal chains' do
      vps = create_boot_vps(autostart_enable: false)
      chain = TransactionChain.create!(name: 'boot_rpc', type: 'TransactionChain', state: :fatal, size: 0)
      vps.acquire_lock(chain)

      expect(reconcile(vps.id)).to eq([disposition(vps.id, 'retain', 'resource_locked')])
    end

    it 'ignores resource locks for a different model with the same ID' do
      vps = create_boot_vps(autostart_enable: false)
      ResourceLock.create!(resource: 'Dataset', row_id: vps.id)

      expect(reconcile(vps.id)).to eq([disposition(vps.id, 'retire', 'autostart_disabled')])
    end

    it 'retains unconfirmed rows before evaluating node, state or autostart' do
      creating = create_boot_vps(node: SpecSeed.other_node, confirmed: :confirm_create)
      destroying = create_boot_vps(confirmed: :confirm_destroy, autostart_enable: false)

      expect(reconcile(creating.id, destroying.id)).to eq(
        [creating, destroying].map { |vps| disposition(vps.id, 'retain', 'transitional') }
      )
    end

    it 'retires confirmed unlocked rows with explicit reasons and no foreign details' do
      elsewhere = create_boot_vps(node: SpecSeed.other_node, autostart_enable: false)
      inactive = create_boot_vps(object_state: :soft_delete, autostart_enable: false)
      hard_deleted = create_boot_vps(object_state: :hard_delete)
      disabled = create_boot_vps(autostart_enable: false)
      absent = Vps.unscoped.maximum(:id) + 1

      expect(reconcile(elsewhere.id, inactive.id, hard_deleted.id, disabled.id, absent)).to eq(
        [
          disposition(elsewhere.id, 'retire', 'assigned_elsewhere'),
          disposition(inactive.id, 'retire', 'inactive'),
          disposition(hard_deleted.id, 'retire', 'inactive'),
          disposition(disabled.id, 'retire', 'autostart_disabled'),
          disposition(absent, 'retire', 'deleted')
        ]
      )
    end

    it 'returns unknown for an expected VPS with invalid pool association' do
      vps = create_boot_vps
      vps.update_column(:dataset_in_pool_id, nil)

      expect(reconcile(vps.id)).to eq([disposition(vps.id, 'unknown', 'inventory_invalid')])
    end

    it 'returns unknown for an expected VPS with a dot path component' do
      vps = create_boot_vps
      Pool.where(id: pool.id).update_all(filesystem: 'tank/../vps')

      expect(reconcile(vps.id)).to eq([disposition(vps.id, 'unknown', 'inventory_invalid')])
    end

    it 'uses one statement for requested rows, pools and locks' do
      vps = create_boot_vps
      queries = select_queries { reconcile(vps.id, vps.id + 1) }

      expect(queries.size).to eq(1)
      expect(queries.first).to include('LEFT JOIN resource_locks', 'LEFT JOIN pools')
    end

    it 'preserves the same snapshot across confirmation and lock release' do
      vps = create_boot_vps(confirmed: :confirm_destroy, autostart_enable: false)
      lock = vps.acquire_lock
      callback = lambda do |event|
        next unless event.payload.fetch(:sql).include?('AS boot_autostart_ids')

        # Commit-like changes after SELECT must not mix old VPS values with a
        # later missing lock and incorrectly retire the obligation.
        vps.update!(confirmed: :confirmed, autostart_enable: true)
        lock.release
      end
      result = nil
      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
        result = reconcile(vps.id)
      end

      expect(result).to eq([disposition(vps.id, 'retain', 'resource_locked')])
      expect(described_class.new(node).reconcile_vps_boot_autostart([vps.id])).to eq(
        schema_version: 1,
        vpses: [disposition(vps.id, 'retain', 'expected', pool_fs: pool.filesystem)]
      )
    end

    it 'accepts a full batch and returns every requested ID exactly once' do
      ids = (1..1000).to_a

      expect(handler.reconcile_vps_boot_autostart(ids).fetch(:vpses)).to eq(
        ids.map { |id| disposition(id, 'retire', 'deleted') }
      )
    end

    [nil, {}, '1', [], [0], [-1], [1.0], ['1'], [true], [1, 1], [2, 1], (1..1001).to_a].each do |ids|
      it "rejects malformed ID input #{ids.inspect[0, 60]}" do
        expect { handler.reconcile_vps_boot_autostart(ids) }.to raise_error(ArgumentError)
      end
    end
  end
end
