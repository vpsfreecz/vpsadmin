# frozen_string_literal: true

class DatasetExpanderSpecExchange
  def marker; end
end

class DatasetExpanderSpecChannel
  def direct(_name); end
end

class DatasetExpanderSpecCommandResult
  attr_reader :exitstatus, :output

  def initialize(error:, exitstatus:, output:)
    @error = error
    @exitstatus = exitstatus
    @output = output
  end

  def error?
    @error
  end
end

RSpec.describe NodeCtld::DatasetExpander do
  let(:exchange) { instance_double(DatasetExpanderSpecExchange) }
  let(:channel) { instance_double(DatasetExpanderSpecChannel, direct: exchange) }
  let(:command_result) do
    DatasetExpanderSpecCommandResult.new(error: false, exitstatus: 0, output: '')
  end
  let(:one_gib) { 1024 * 1024 * 1024 }

  before do
    # rubocop:disable RSpec/ReceiveMessages
    allow(NodeCtld::NodeBunny).to receive(:create_channel).and_return(channel)
    allow(NodeCtld::NodeBunny).to receive(:exchange_name).and_return('node:spec')
    # rubocop:enable RSpec/ReceiveMessages
    $CFG = NodeCtldSpec::FakeCfg.new(
      dataset_expander: {
        enable: true,
        min_avail_bytes: 2 * one_gib,
        min_avail_percent: 10,
        min_pool_avail_bytes: 8 * one_gib,
        min_pool_avail_percent: 5,
        min_expand_bytes: 4 * one_gib,
        min_expand_percent: 10
      }
    )
  end

  it 'skips expansion when pool headroom would fall below the minimum' do
    expander = described_class.new
    pool = build_pool(used_bytes: 90 * one_gib, available_bytes: 10 * one_gib)

    allow(expander).to receive(:zfs)

    expander.check(pool)

    expect(expander).not_to have_received(:zfs)
  end

  it 'updates in-memory pool usage after a successful expansion' do
    expander = described_class.new
    pool = build_pool(used_bytes: 80 * one_gib, available_bytes: 20 * one_gib)

    allow(expander).to receive(:zfs).and_return(command_result)

    expander.check(pool)

    expect(pool.used_bytes).to eq(84 * one_gib)
    expect(pool.available_bytes).to eq(16 * one_gib)
  end

  def build_pool(used_bytes:, available_bytes:)
    dataset = NodeCtld::StorageStatus::Dataset.new(
      :filesystem,
      'tank/ct1',
      10,
      20,
      30,
      {
        'available' => NodeCtld::StorageStatus::Property.new(1, 'available', 1 * one_gib),
        'refquota' => NodeCtld::StorageStatus::Property.new(2, 'refquota', 20 * one_gib)
      }
    )

    NodeCtld::StorageStatus::Pool.new(
      'tank',
      'tank',
      'hypervisor',
      true,
      { dataset.name => dataset },
      used_bytes,
      available_bytes
    )
  end
end
