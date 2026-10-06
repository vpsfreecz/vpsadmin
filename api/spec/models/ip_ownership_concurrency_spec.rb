require 'spec_helper'
require 'timeout'

RSpec.describe Network do
  let(:committed) { {} }
  let(:connection_threads) { [] }

  before do
    unlock_transaction_signer!
    connection_thread do
      seed_network = SpecSeed.network_v4
      committed[:seed_network_id] = seed_network.id
      committed[:seed_enabled] = seed_network.enabled
      committed[:seed_ips] = IpAddress.where(network: seed_network).order(:id).map(&:attributes)
      committed[:seed_versions] = PaperTrail::Version.where(item_type: 'Network', item_id: seed_network.id).pluck(:id)
      config = SpecSeed.user.environment_user_configs.find_by!(environment: SpecSeed.environment)
      committed[:config_id] = config.id
      committed[:uses] = ClusterResourceUse.where(class_name: 'EnvironmentUserConfig', row_id: config.id).map(&:attributes)
      ip = create_ip_address!(user: SpecSeed.user, addr: '192.0.2.248')
      committed[:ip_id] = ip.id
      committed[:usage] = config.reload.ipv4
      network = SpecSeed.network_v4.dup
      network.update!(address: '198.51.100.0')
      committed[:network_id] = network.id
      LocationNetwork.create!(network:, location: SpecSeed.location, autopick: true, userpick: true)
    end.value
  end

  def connection_thread(&block)
    thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        with_current_context do |session|
          block.call
        ensure
          session.destroy!
        end
      end
    end
    connection_threads << thread
    thread
  end

  after do
    # A failed join must not skip the other worker or committed-fixture cleanup.
    thread_error = nil
    connection_threads.each do |thread|
      thread.join(25) || thread.kill.join
    rescue StandardError, RSpec::Expectations::ExpectationNotMetError => e
      thread_error ||= e
    end
    restoration_errors = []
    connection_thread do
      ips = IpAddress.where(id: [committed[:ip_id], committed[:second_ip_id]]).or(IpAddress.where(network_id: committed[:network_id]))
      ids = ips.pluck(:id)
      host_ids = HostIpAddress.where(ip_address_id: ids).pluck(:id)
      locks = ResourceLock.where(resource: 'IpAddress', row_id: ids)
                          .or(ResourceLock.where(resource: 'HostIpAddress', row_id: host_ids))
                          .or(ResourceLock.where(resource: 'Network', row_id: committed[:network_id]))
      leaked_locks = locks.pluck(:resource, :row_id)
      locks.delete_all
      HostIpAddress.where(ip_address_id: ids).delete_all
      ips.delete_all
      LocationNetwork.where(network_id: committed[:network_id]).delete_all
      described_class.where(id: committed[:network_id]).delete_all
      PaperTrail::Version.where(item_type: 'IpAddress', item_id: ids).delete_all
      PaperTrail::Version.where(item_type: 'Network', item_id: committed[:network_id]).delete_all
      if committed[:seed_network_id]
        described_class.where(id: committed[:seed_network_id]).update_all(enabled: committed[:seed_enabled])
        PaperTrail::Version.where(item_type: 'Network', item_id: committed[:seed_network_id])
                           .where.not(id: committed[:seed_versions]).delete_all
      end
      [[committed[:config_id], committed[:uses]], [committed[:extra_config_id], committed[:extra_uses]]].each do |id, uses|
        next unless uses

        ClusterResourceUse.where(class_name: 'EnvironmentUserConfig', row_id: id)
                          .where.not(id: uses.map { |attrs| attrs['id'] }).delete_all
        uses.each { |attrs| ClusterResourceUse.where(id: attrs['id']).update_all(attrs) }
        actual = ClusterResourceUse.where(class_name: 'EnvironmentUserConfig', row_id: id).order(:id).map(&:attributes)
        expected = uses.sort_by { |attrs| attrs['id'] }
        if actual != expected
          restoration_errors << "EnvironmentUserConfig ##{id} usage was not restored: expected #{expected.inspect}, got #{actual.inspect}"
        end
      end
      restoration_errors << "Fixture reservations survived workers: #{leaked_locks.inspect}" unless leaked_locks.empty?
      remaining_ids = IpAddress.where(id: ids).pluck(:id)
      restoration_errors << "Fixture allocations survived cleanup: #{remaining_ids.inspect}" unless remaining_ids.empty?
      remaining_hosts = HostIpAddress.where(ip_address_id: ids).pluck(:id)
      restoration_errors << "Fixture host addresses survived cleanup: #{remaining_hosts.inspect}" unless remaining_hosts.empty?
      if described_class.exists?(id: committed[:network_id])
        restoration_errors << "Fixture network ##{committed[:network_id]} survived cleanup"
      end
      if committed[:seed_network_id]
        if described_class.find(committed[:seed_network_id]).enabled != committed[:seed_enabled]
          restoration_errors << "Seed network ##{committed[:seed_network_id]} availability was not restored"
        end
        actual = IpAddress.where(network_id: committed[:seed_network_id]).order(:id).map(&:attributes)
        if actual != committed[:seed_ips]
          restoration_errors << "Seed allocations were not restored: expected #{committed[:seed_ips].inspect}, got #{actual.inspect}"
        end
      end
    end.value
    unless restoration_errors.empty?
      restoration_errors << "Worker failed: #{thread_error.class}: #{thread_error.message}" if thread_error
      raise "Committed fixture restoration failed:\n#{restoration_errors.join("\n")}"
    end
    raise thread_error if thread_error
  end

  it 'rejects a role change waiting behind the first direct registration' do
    locked = Queue.new
    attempted = Queue.new
    resume = Queue.new
    allow_any_instance_of(described_class).to receive(:reload).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
      result = original.call(*args)
      if Thread.current[:network_race] == :register
        Thread.current[:network_race] = nil
        locked << true
        resume.pop
      end
      result
    end
    allow_any_instance_of(described_class).to receive(:preserve_allocation_resource).and_wrap_original do |original| # rubocop:disable RSpec/AnyInstance
      attempted << true if Thread.current[:network_race] == :update
      original.call
    end
    workers = []
    workers << connection_thread do
      network = described_class.find(committed[:network_id])
      Thread.current[:network_race] = :register
      IpAddress.register(IPAddress.parse('198.51.100.1'), network:, user: SpecSeed.user,
                                                          environment: SpecSeed.environment, prefix: 32, size: 1)
    end
    Timeout.timeout(10) { locked.pop }
    workers << connection_thread do
      Thread.current[:network_race] = :update
      network = described_class.find(committed[:network_id])
      expect { network.update!(role: :private_access) }
               .to raise_error(ActiveRecord::RecordInvalid, /while the network has allocations/)
    end
    Timeout.timeout(10) { attempted.pop }
    expect(workers.last.join(0.1)).to be_nil
    resume << true
    Timeout.timeout(20) { workers.each(&:value) }
    connection_thread do
      expect(described_class.find(committed[:network_id]).role).to eq('public_access')
      expect(EnvironmentUserConfig.find(committed[:config_id]).ipv4).to eq(committed[:usage] + 1)
    end.value
  ensure
    resume << true if resume
    workers&.each { |thread| thread.join(25) || thread.kill.join }
  end

  it 'rejects new ownership when disable commits before admission', :network_admission do
    selected = Queue.new
    resume = Queue.new
    worker = connection_thread do
      ip = IpAddress.find(committed[:ip_id])
      selected << true
      resume.pop
      expect do
        TransactionChains::Ip::Update.fire(ip, user: SpecSeed.other_user, environment: SpecSeed.environment)
      end.to raise_error(VpsAdmin::API::Exceptions::IpAddressInvalid, /disabled for new allocations/)
    end
    Timeout.timeout(10) { selected.pop }
    connection_thread { IpAddress.find(committed[:ip_id]).network.update!(enabled: false) }.value
    resume << true
    Timeout.timeout(20) { worker.value }
    connection_thread { expect(IpAddress.find(committed[:ip_id]).user_id).to eq(SpecSeed.user.id) }.value
  ensure
    resume << true if resume
    worker&.join(25) || worker&.kill&.join
    connection_thread { IpAddress.find(committed[:ip_id]).network.update!(enabled: true) }.value
  end

  it 'lets admitted ownership finish before a waiting disable', :network_admission do
    connection_thread do
      config = SpecSeed.other_user.environment_user_configs.find_by!(environment: SpecSeed.environment)
      committed[:extra_config_id] = config.id
      committed[:extra_uses] = ClusterResourceUse.where(class_name: 'EnvironmentUserConfig', row_id: config.id).map(&:attributes)
    end.value
    admitted = Queue.new
    disabling = Queue.new
    resume = Queue.new
    allow_any_instance_of(IpAddress).to receive(:ensure_network_enabled!).and_wrap_original do |original| # rubocop:disable RSpec/AnyInstance
      result = original.call
      if Thread.current[:network_admission] == :own
        Thread.current[:network_admission] = nil
        admitted << true
        resume.pop
      end
      result
    end
    workers = []
    workers << connection_thread do
      Thread.current[:network_admission] = :own
      TransactionChains::Ip::Update.fire(IpAddress.find(committed[:ip_id]),
                                         user: SpecSeed.other_user, environment: SpecSeed.environment)
    end
    Timeout.timeout(10) { admitted.pop }
    workers << connection_thread do
      network = IpAddress.find(committed[:ip_id]).network
      disabling << true
      network.update!(enabled: false)
    end
    Timeout.timeout(10) { disabling.pop }
    expect(workers.last.join(0.1)).to be_nil
    resume << true
    Timeout.timeout(20) { workers.each(&:value) }
    connection_thread do
      ip = IpAddress.find(committed[:ip_id])
      expect(ip.user_id).to eq(SpecSeed.other_user.id)
      expect(ip.network.enabled?).to be(false)
    end.value
  ensure
    resume << true if resume
    workers&.each { |thread| thread.join(25) || thread.kill.join }
    connection_thread { IpAddress.find(committed[:ip_id]).network.update!(enabled: true) }.value
  end

  it 'allows parallel admissions in one pool without upgrading network locks', :network_admission do
    ids = connection_thread do
      network = described_class.find(committed[:network_id])
      network.add_ips(2).map(&:id)
    end.value
    ready = Queue.new
    resume = Queue.new
    workers = ids.map do |id|
      connection_thread do
        TransactionChain.transaction do
          chain = build_transaction_chain!(name: 'parallel-network-admission')
          ip = IpAddress.find(id)
          ip.lock_for_new_use!(chain)
          ip.ensure_pickable!(user: SpecSeed.user, location: SpecSeed.location, ip_v: 4, role: :public_access,
                              purpose: :vps)
          ready << id
          resume.pop
          raise ActiveRecord::Rollback
        end
      end
    end
    # Both must pass the authoritative joined policy read while the other holds
    # a shared network lock and a different exclusive IP row lock.
    admitted_ids = Timeout.timeout(10) { ids.map { ready.pop } }
    expect(admitted_ids.sort).to eq(ids.sort)
    ids.each { resume << true }
    Timeout.timeout(20) { workers.each(&:value) }
  ensure
    ids&.each { resume << true } if resume
    workers&.each { |thread| thread.join(25) || thread.kill.join }
  end

  it 'serializes owned registration before a waiting disable', :network_admission do
    registered = Queue.new
    disabling = Queue.new
    resume = Queue.new
    allow_any_instance_of(described_class).to receive(:ensure_enabled!).and_wrap_original do |original| # rubocop:disable RSpec/AnyInstance
      result = original.call
      if Thread.current[:network_admission] == :register
        Thread.current[:network_admission] = nil
        registered << true
        resume.pop
      end
      result
    end
    workers = []
    workers << connection_thread do
      Thread.current[:network_admission] = :register
      network = described_class.find(committed[:network_id])
      IpAddress.register(IPAddress.parse('198.51.100.1'), network:, user: SpecSeed.user,
                                                          environment: SpecSeed.environment, prefix: 32, size: 1)
    end
    Timeout.timeout(10) { registered.pop }
    workers << connection_thread do
      network = described_class.find(committed[:network_id])
      disabling << true
      network.update!(enabled: false)
    end
    Timeout.timeout(10) { disabling.pop }
    expect(workers.last.join(0.1)).to be_nil
    resume << true
    Timeout.timeout(20) { workers.each(&:value) }
    connection_thread do
      expect(described_class.find(committed[:network_id]).enabled?).to be(false)
      expect(IpAddress.find_by!(network_id: committed[:network_id], ip_addr: '198.51.100.1').user_id)
        .to eq(SpecSeed.user.id)
    end.value
  ensure
    resume << true if resume
    workers&.each { |thread| thread.join(25) || thread.kill.join }
  end

  it 'rejects owned registration after disable commits without changing quota', :network_admission do
    connection_thread do
      network = described_class.find(committed[:network_id])
      network.update!(enabled: false)
      expect do
        IpAddress.register(IPAddress.parse('198.51.100.1'), network:, user: SpecSeed.user,
                                                            environment: SpecSeed.environment, prefix: 32, size: 1)
      end.to raise_error(VpsAdmin::API::Exceptions::IpAddressInvalid, /disabled for new allocations/)
      expect(IpAddress.where(network:)).to be_empty
      expect(EnvironmentUserConfig.find(committed[:config_id]).ipv4).to eq(committed[:usage])
    end.value
  end

  it 'charges additions to the new resource after a concurrent empty-network role change' do
    locked = Queue.new
    attempted = Queue.new
    resume = Queue.new
    private_usage = connection_thread { EnvironmentUserConfig.find(committed[:config_id]).ipv4_private }.value
    allow_any_instance_of(described_class).to receive(:preserve_allocation_resource).and_wrap_original do |original| # rubocop:disable RSpec/AnyInstance
      result = original.call
      if Thread.current[:network_race] == :update
        Thread.current[:network_race] = nil
        locked << true
        resume.pop
      end
      result
    end
    allow_any_instance_of(described_class).to receive(:reload).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
      attempted << true if Thread.current[:network_race] == :register
      original.call(*args)
    end
    workers = []
    workers << connection_thread do
      Thread.current[:network_race] = :update
      described_class.find(committed[:network_id]).update!(role: :private_access)
    end
    Timeout.timeout(10) { locked.pop }
    workers << connection_thread do
      network = described_class.find(committed[:network_id])
      expect(network.role).to eq('public_access')
      Thread.current[:network_race] = :register
      network.add_ips(1, user: SpecSeed.user, environment: SpecSeed.environment)
    end
    Timeout.timeout(10) { attempted.pop }
    expect(workers.last.join(0.1)).to be_nil
    resume << true
    Timeout.timeout(20) { workers.each(&:value) }
    connection_thread do
      config = EnvironmentUserConfig.find(committed[:config_id])
      expect(config.ipv4_private).to eq(private_usage + 1)
      expect(config.ipv4).to eq(committed[:usage])
      expect(described_class.find(committed[:network_id]).role).to eq('private_access')
    end.value
  ensure
    resume << true if resume
    workers&.each { |thread| thread.join(25) || thread.kill.join }
  end

  it 'reloads a migration replacement selected before a concurrent disown' do
    selected = Queue.new
    resume = Queue.new
    allow(IpAddress).to receive(:pick_from_admitted_networks!) do
      ip = IpAddress.find(committed[:ip_id])
      expect(ip.user_id).to eq(SpecSeed.user.id)
      selected << true
      resume.pop
      ip
    end

    worker = connection_thread do
      TransactionChain.transaction do
        migration = TransactionChains::Vps::Migrate::Base.create!(
          name: 'migration-replacement-spec', state: :staged, size: 0,
          user: User.current, user_session: UserSession.current
        )
        migration.global_locks = []
        networks = described_class.lock_for_admission!([IpAddress.find(committed[:ip_id]).network_id])
        allow(migration).to receive_messages(
          dst_vps: Vps.new(user: SpecSeed.user, node: SpecSeed.node),
          admission_networks: networks, replacement_network_ids: networks.keys
        )
        replacement = migration.send(:pick_replacement_ip, IpAddress.find(committed[:ip_id]))
        expect(replacement.user_id).to be_nil
        expect(replacement.charged_environment_id).to be_nil
        expect(replacement.get_current_lock.locked_by_id).to eq(migration.id)
        raise ActiveRecord::Rollback
      end
    end
    Timeout.timeout(10) { selected.pop }
    connection_thread do
      TransactionChains::Ip::Update.fire(IpAddress.find(committed[:ip_id]), user: nil)
    end.value
    resume << true
    Timeout.timeout(20) { worker.value }
  ensure
    resume << true if resume
    worker&.join(25) || worker&.kill&.join
  end

  it 'rejects an export grant selected before a concurrent release' do
    connection_thread do
      TransactionChain.transaction do
        fixture = create_netif_vps_fixture!(user: SpecSeed.user)
        ip = IpAddress.find(committed[:ip_id])
        export, = create_export_for_dataset!(dataset_in_pool: fixture[:dataset_in_pool], host_ip: ip)
        host = ExportHost.new(export:, ip_address: ip, rw: true, sync: true,
                              subtree_check: false, root_squash: false)
        allow(host).to receive(:lock_ip!).and_wrap_original do |original, chain|
          connection_thread do
            changed = IpAddress.find(ip.id)
            changed.acquire_lock do
              changed.update!(user: nil, charged_environment: nil)
            end
          end.value
          original.call(chain)
        end
        expect { TransactionChains::Export::AddHosts.fire(export, [host]) }
          .to raise_error(ActiveRecord::RecordInvalid, /ownership or assignment changed/)
        expect(ExportHost.where(export:)).to be_empty
        raise ActiveRecord::Rollback
      end
    end.value
  end

  it 'rechecks userpick after a concurrent release of a previously owned address' do
    connection_thread do
      TransactionChain.transaction do
        with_current_context(user: SpecSeed.user) do
          fixture = create_netif_vps_fixture!(user: SpecSeed.user)
          LocationNetwork.where(network_id: SpecSeed.network_v4.id, location_id: SpecSeed.location.id)
                         .update_all(userpick: false)
          ip = IpAddress.find(committed[:ip_id])
          paused = false
          allow_any_instance_of(TransactionChains::NetworkInterface::AddRoute).to receive(:lock).and_wrap_original do |original, resource| # rubocop:disable RSpec/AnyInstance
            if resource.is_a?(IpAddress) && resource.id == ip.id && !paused
              paused = true
              connection_thread do
                changed = IpAddress.find(ip.id)
                changed.acquire_lock do
                  changed.update!(user: nil, charged_environment: nil)
                end
              end.value
            end
            original.call(resource)
          end
          expect { fixture[:netif].add_route(ip, safe: true) }
            .to raise_error(VpsAdmin::API::Exceptions::IpAddressInvalid, /cannot be freely assigned/)
          expect(ip.reload.network_interface_id).to be_nil
        end
        raise ActiveRecord::Rollback
      end
    end.value
  end

  it 'charges network additions against current usage after a concurrent disown' do
    connection_thread do
      expect(IpAddress.find(committed[:ip_id]).charged_environment_id).to eq(SpecSeed.environment.id)
    end.value
    snapshot = Queue.new
    resume = Queue.new
    worker = connection_thread do
      described_class.transaction do
        config = EnvironmentUserConfig.find(committed[:config_id])
        config.ipv4 # Establish an older REPEATABLE READ snapshot.
        snapshot << true
        resume.pop
        ips = described_class.find(committed[:network_id]).add_ips(1, user: SpecSeed.user, environment: SpecSeed.environment)
        expect(ips.first.charged_environment_id).to eq(SpecSeed.environment.id)
      end
    end
    Timeout.timeout(10) { snapshot.pop }
    connection_thread do
      TransactionChains::Ip::Update.fire(IpAddress.find(committed[:ip_id]), user: nil)
    end.value
    resume << true
    Timeout.timeout(20) { worker.value }
    connection_thread do
      expect(EnvironmentUserConfig.find(committed[:config_id]).ipv4).to eq(committed[:usage])
    end.value
  ensure
    resume << true if resume
    worker&.join(25) || worker&.kill&.join
  end

  it 'serializes opposite ownership transfers before either takes a second quota row' do
    connection_thread do
      config = SpecSeed.other_user.environment_user_configs.find_by!(environment: SpecSeed.environment)
      committed[:extra_config_id] = config.id
      committed[:extra_uses] = ClusterResourceUse.where(class_name: 'EnvironmentUserConfig', row_id: config.id).map(&:attributes)
      committed[:second_ip_id] = create_ip_address!(user: SpecSeed.other_user, addr: '192.0.2.247').id
      committed[:extra_usage] = config.reload.ipv4
    end.value
    locked = Queue.new
    attempted = Queue.new
    resume = Queue.new
    # Observe the real SQL lock boundaries on the separate database sessions.
    allow_any_instance_of(EnvironmentUserConfig).to receive(:lock!).and_wrap_original do |original, *args, **kwargs| # rubocop:disable RSpec/AnyInstance
      worker = Thread.current[:ownership_transfer_worker]
      Thread.current[:ownership_transfer_worker] = nil if worker
      attempted << true if worker == :second
      result = original.call(*args, **kwargs)
      if worker == :first
        locked << true
        resume.pop
      end
      result
    end
    workers = []
    workers << connection_thread do
      Thread.current[:ownership_transfer_worker] = :first
      TransactionChains::Ip::Update.fire(IpAddress.find(committed[:ip_id]),
                                         user: SpecSeed.other_user, environment: SpecSeed.environment)
    end
    Timeout.timeout(10) { locked.pop }
    workers << connection_thread do
      Thread.current[:ownership_transfer_worker] = :second
      TransactionChains::Ip::Update.fire(IpAddress.find(committed[:second_ip_id]),
                                         user: SpecSeed.user, environment: SpecSeed.environment)
    end
    Timeout.timeout(10) { attempted.pop }
    expect(workers.last.join(0.1)).to be_nil
    resume << true
    Timeout.timeout(20) { workers.each(&:value) }
    connection_thread do
      expect(IpAddress.find(committed[:ip_id]).user_id).to eq(SpecSeed.other_user.id)
      expect(IpAddress.find(committed[:second_ip_id]).user_id).to eq(SpecSeed.user.id)
      expect(EnvironmentUserConfig.find(committed[:config_id]).ipv4).to eq(committed[:usage])
      expect(EnvironmentUserConfig.find(committed[:extra_config_id]).ipv4).to eq(committed[:extra_usage])
    end.value
  ensure
    resume << true if resume
    workers&.each { |thread| thread.join(25) || thread.kill.join }
  end

  it 'does not confirm ownership removal for an allocation transferred after the resource-free selection' do
    connection_thread do
      TransactionChain.transaction do
        paused = false
        allow_any_instance_of(TransactionChains::Ip::Free).to receive(:lock).and_wrap_original do |original, resource| # rubocop:disable RSpec/AnyInstance
          if resource.is_a?(IpAddress) && resource.id == committed[:ip_id] && !paused
            paused = true
            connection_thread { IpAddress.find(resource.id).update!(user: SpecSeed.other_user) }.value
          end
          original.call(resource)
        end
        chain, = use_chain_method_in_root!(TransactionChains::Ip::Free,
                                           method: :free_from_environment_user_config,
                                           args: [ClusterResource.find_by!(name: 'ipv4'),
                                                  EnvironmentUserConfig.find(committed[:config_id])])
        expect(paused).to be(true), IpAddress.where(id: committed[:ip_id]).pluck(:user_id, :charged_environment_id, :network_id).inspect
        expect(confirmations_for(chain).select { |row| row.class_name == 'IpAddress' }).to be_empty
        expect(IpAddress.find(committed[:ip_id]).reload(lock: true).user_id).to eq(SpecSeed.other_user.id)
        raise ActiveRecord::Rollback
      end
    end.value
  end
end
