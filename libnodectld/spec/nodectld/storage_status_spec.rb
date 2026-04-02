# frozen_string_literal: true

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

  def tree_with_datasets(datasets)
    StorageStatusSpecTree.new(
      datasets.map do |name, properties|
        StorageStatusSpecTreeDataset.new(name:, properties:)
      end
    )
  end
end
