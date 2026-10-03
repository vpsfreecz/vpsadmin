# frozen_string_literal: true

require 'nodectld/rpc_client'

class StorageStatusSpecExchange
  def marker; end
end

class StorageStatusSpecChannel
  def direct(_name); end
end

class StorageStatusSpecTree
  def initialize(datasets)
    @datasets = datasets
  end

  def each_tree_dataset(&)
    @datasets.each(&)
  end
end

class StorageStatusSpecTreeDataset
  attr_reader :name, :properties

  def initialize(name:, properties:)
    @name = name
    @properties = properties
  end
end

RSpec.describe NodeCtld::StorageStatus do
  let(:exchange) { instance_double(StorageStatusSpecExchange) }
  let(:channel) { instance_double(StorageStatusSpecChannel, direct: exchange) }

  before do
    $CFG.patch(storage: { update_interval: 1 })
    # rubocop:disable RSpec/ReceiveMessages
    allow(NodeCtld::NodeBunny).to receive(:create_channel).and_return(channel)
    allow(NodeCtld::NodeBunny).to receive(:exchange_name).and_return('node:spec')
    # rubocop:enable RSpec/ReceiveMessages
  end

  it 'keeps whole-zpool root metrics when reading pool datasets' do
    dataset_expander = instance_spy(NodeCtld::DatasetExpander)
    property_reader = instance_double(OsCtl::Lib::Zfs::PropertyReader)
    dataset = NodeCtld::StorageStatus::Dataset.new(
      :filesystem,
      'tank/ct1',
      10,
      20,
      30,
      {
        'available' => NodeCtld::StorageStatus::Property.new(1, 'available', nil),
        'refquota' => NodeCtld::StorageStatus::Property.new(2, 'refquota', nil)
      }
    )
    pool = NodeCtld::StorageStatus::Pool.new(
      'tank',
      'tank',
      'hypervisor',
      true,
      { 'tank/ct1' => dataset },
      nil,
      nil
    )

    allow(OsCtl::Lib::Zfs::PropertyReader).to receive(:new).and_return(property_reader)
    allow(property_reader).to receive(:read)
      .with(['tank'], described_class::READ_PROPERTIES, recursive: true)
      .and_return(tree_with_datasets([
                                       ['tank', { 'used' => '1048576', 'available' => '2097152' }],
                                       ['tank/ct1', { 'available' => '524288', 'refquota' => '3145728' }]
                                     ]))
    allow(dataset_expander).to receive(:check)

    status = described_class.new(dataset_expander)
    status.send(:read, 1 => pool)

    expect(dataset_expander).to have_received(:check) do |seen_pool|
      expect(seen_pool.used_bytes).to eq(1_048_576)
      expect(seen_pool.available_bytes).to eq(2_097_152)
    end

    expect(pool.used_bytes).to eq(1_048_576)
    expect(pool.available_bytes).to eq(2_097_152)
    expect(dataset.properties['available'].value).to eq(524_288)
    expect(dataset.properties['refquota'].value).to eq(3_145_728)
  end

  it 'ignores the parent zpool dataset for storage pools under a dataset' do
    dataset_expander = instance_spy(NodeCtld::DatasetExpander)
    property_reader = instance_double(OsCtl::Lib::Zfs::PropertyReader)
    dataset = NodeCtld::StorageStatus::Dataset.new(
      :filesystem,
      'tank/ct/vm1',
      10,
      20,
      30,
      {
        'available' => NodeCtld::StorageStatus::Property.new(1, 'available', nil),
        'refquota' => NodeCtld::StorageStatus::Property.new(2, 'refquota', nil)
      }
    )
    pool = NodeCtld::StorageStatus::Pool.new(
      'tank',
      'tank/ct',
      'primary',
      true,
      { 'tank/ct/vm1' => dataset },
      nil,
      nil
    )

    allow(OsCtl::Lib::Zfs::PropertyReader).to receive(:new).and_return(property_reader)
    allow(property_reader).to receive(:read)
      .with(['tank/ct'], described_class::READ_PROPERTIES, recursive: true)
      .and_return(tree_with_datasets([
                                       ['tank', { 'used' => '2048', 'available' => '4096' }],
                                       ['tank/ct', { 'used' => '1024', 'available' => '3072' }],
                                       ['tank/ct/vm1', { 'available' => '512', 'refquota' => '4096' }]
                                     ]))
    allow(dataset_expander).to receive(:check)

    status = described_class.new(dataset_expander)
    allow(status).to receive(:log)
    status.send(:read, 1 => pool)

    expect(status).not_to have_received(:log).with(:warn, "'tank' not registered in the database")
    expect(pool.used_bytes).to eq(1_024)
    expect(pool.available_bytes).to eq(3_072)
    expect(dataset.properties['available'].value).to eq(512)
    expect(dataset.properties['refquota'].value).to eq(4_096)
  end

  it 'preserves the complete previous catalog when a later pool RPC fails' do
    status = new_status
    previous = { 99 => Object.new }
    status.instance_variable_set(:@pools, previous)
    rpc = catalog_rpc
    allow(rpc).to receive(:list_pool_dataset_properties).with(2, anything)
                                                        .and_raise(NodeCtld::RpcClient::TransportError)
    allow(NodeCtld::RpcClient).to receive(:run) { |**_opts, &block| block.call(rpc) }
    updates = status.instance_variable_get(:@update_queue)
    allow(updates).to receive(:pop).and_return(:update, :stop)

    status.send(:run_updater)
    expect(status.instance_variable_get(:@pools)).to equal(previous)
    expect(status.instance_variable_get(:@read_queue).length).to eq(0)
  end

  it 'publishes a later complete view only after its RPC cleanup succeeds' do
    status = new_status
    previous = { 99 => Object.new }
    status.instance_variable_set(:@pools, previous)
    rpc = catalog_rpc
    calls = 0
    allow(NodeCtld::RpcClient).to receive(:run) do |**_opts, &block|
      calls += 1
      expect(status.instance_variable_get(:@pools)).to equal(previous)
      block.call(rpc)
      raise NodeCtld::RpcClient::CleanupError if calls == 1
    end
    updates = status.instance_variable_get(:@update_queue)
    allow(updates).to receive(:pop).and_return(:update, :update, :stop)

    status.send(:run_updater)
    expect(status.instance_variable_get(:@pools).keys).to eq([1, 2])
    expect(status.instance_variable_get(:@read_queue).length).to eq(1)
    expect(calls).to eq(2)
  end

  it 'propagates malformed catalog and permanent protocol errors instead of retrying' do
    status = new_status
    rpc = catalog_rpc
    allow(rpc).to receive(:list_pools).and_return([Object.new])
    allow(NodeCtld::RpcClient).to receive(:run) { |**_opts, &block| block.call(rpc) }
    updates = status.instance_variable_get(:@update_queue)
    allow(updates).to receive(:pop).and_return(:update, :stop)

    expect { status.send(:run_updater) }.to raise_error(NoMethodError, /undefined method .*\[\]/)
    original = Bunny::AccessRefused.new('fixture refused', nil, nil)
    allow(rpc).to receive(:list_pools).and_raise(original)
    allow(updates).to receive(:pop).and_return(:update, :stop)
    expect { status.send(:run_updater) }.to(raise_error { |error| expect(error).to equal(original) })
    expect(status.instance_variable_get(:@read_queue).length).to eq(0)
  end

  it 'passes cooperative stop into RPC and never publishes a post-stop view' do
    status = new_status
    previous = { 99 => Object.new }
    status.instance_variable_set(:@pools, previous)
    rpc = catalog_rpc
    allow(NodeCtld::RpcClient).to receive(:run) do |stopped:, &block|
      expect(stopped.call).to be_falsey
      block.call(rpc)
      status.instance_variable_set(:@stop, true)
      expect(stopped.call).to be(true)
    end
    updates = status.instance_variable_get(:@update_queue)
    allow(updates).to receive(:pop).and_return(:update)

    status.send(:run_updater)
    expect(NodeCtld::RpcClient).to have_received(:run).once
    expect(status.instance_variable_get(:@pools)).to equal(previous)
    expect(status.instance_variable_get(:@read_queue).length).to eq(0)
  end

  it 'does not retry or publish when stop interrupts failed RPC recovery' do
    status = new_status
    allow(NodeCtld::RpcClient).to receive(:run) do |stopped:, **_opts|
      status.instance_variable_set(:@stop, true)
      expect(stopped.call).to be(true)
      raise NodeCtld::RpcClient::Stopped
    end
    updates = status.instance_variable_get(:@update_queue)
    allow(updates).to receive(:pop).and_return(:update)

    status.send(:run_updater)
    expect(NodeCtld::RpcClient).to have_received(:run).once
    expect(updates).to have_received(:pop).once
    expect(status.instance_variable_get(:@read_queue).length).to eq(0)
  end

  def new_status
    described_class.new(instance_spy(NodeCtld::DatasetExpander))
  end

  def catalog_rpc
    rpc = instance_double(NodeCtld::RpcClient)
    allow(rpc).to receive_messages(
      list_pools: [
        { 'id' => 1, 'role' => 'primary', 'name' => 'tank', 'filesystem' => 'tank/ct' },
        { 'id' => 2, 'role' => 'hypervisor', 'name' => 'other', 'filesystem' => 'other/ct' }
      ],
      list_pool_dataset_properties: []
    )
    rpc
  end

  def tree_with_datasets(datasets)
    StorageStatusSpecTree.new(
      datasets.map do |name, properties|
        StorageStatusSpecTreeDataset.new(name:, properties:)
      end
    )
  end
end
