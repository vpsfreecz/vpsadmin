require 'spec_helper'
require 'timeout'

RSpec.describe Network do
  let(:committed) { {} }

  before do
    unlock_transaction_signer!
    connection_thread do
      config = SpecSeed.user.environment_user_configs.find_by!(environment: SpecSeed.environment)
      committed[:config_id] = config.id
      committed[:uses] = ClusterResourceUse.where(class_name: 'EnvironmentUserConfig', row_id: config.id).map(&:attributes)
      ip = create_ip_address!(user: SpecSeed.user, addr: '192.0.2.248')
      committed[:ip_id] = ip.id
      committed[:usage] = config.reload.ipv4
      network = SpecSeed.network_v4.dup
      network.update!(address: '198.51.100.0')
      LocationNetwork.create!(network:, location: SpecSeed.location, autopick: true, userpick: true)
      committed[:network_id] = network.id
    end.value
  end

  def connection_thread(&block)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        with_current_context do |session|
          block.call
        ensure
          session.destroy!
        end
      end
    end
  end

  after do
    connection_thread do
      ips = IpAddress.where(id: [committed[:ip_id], committed[:second_ip_id]]).or(IpAddress.where(network_id: committed[:network_id]))
      ids = ips.pluck(:id)
      HostIpAddress.where(ip_address_id: ids).delete_all
      ips.delete_all
      LocationNetwork.where(network_id: committed[:network_id]).delete_all
      described_class.where(id: committed[:network_id]).delete_all
      PaperTrail::Version.where(item_type: 'IpAddress', item_id: ids).delete_all
      PaperTrail::Version.where(item_type: 'Network', item_id: committed[:network_id]).delete_all
      [[committed[:config_id], committed[:uses]], [committed[:extra_config_id], committed[:extra_uses]]].each do |id, uses|
        next unless uses

        ClusterResourceUse.where(class_name: 'EnvironmentUserConfig', row_id: id)
                          .where.not(id: uses.map { |attrs| attrs['id'] }).delete_all
        uses.each { |attrs| ClusterResourceUse.where(id: attrs['id']).update_all(attrs) }
      end
    end.value
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
end
