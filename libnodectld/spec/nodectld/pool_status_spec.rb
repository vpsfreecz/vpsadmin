# frozen_string_literal: true

class PoolStatusSpecExchange
  def marker; end
end

class PoolStatusSpecChannel
  def direct(_name); end
end

class PoolStatusSpecRpcClient
  def list_pools; end
end

class PoolStatusSpecEntry
  attr_reader :state, :scan, :scan_percent

  def initialize(state:, scan:, scan_percent:)
    @state = state
    @scan = scan
    @scan_percent = scan_percent
  end
end

class PoolStatusSpecFilesystem
  attr_reader :properties

  def initialize(properties:)
    @properties = properties
  end
end

RSpec.describe NodeCtld::PoolStatus do
  let(:exchange) { instance_double(PoolStatusSpecExchange) }
  let(:channel) { instance_double(PoolStatusSpecChannel, direct: exchange) }

  before do
    # rubocop:disable RSpec/ReceiveMessages
    allow(NodeCtld::NodeBunny).to receive(:create_channel).and_return(channel)
    allow(NodeCtld::NodeBunny).to receive(:exchange_name).and_return('node:spec')
    # rubocop:enable RSpec/ReceiveMessages
  end

  it 'reads pool space from the configured filesystem' do
    rpc = instance_double(
      PoolStatusSpecRpcClient,
      list_pools: [
        {
          'id' => 123,
          'name' => 'tank',
          'filesystem' => 'tank/private-a'
        }
      ]
    )
    zpool_status = instance_double(OsCtl::Lib::Zfs::ZpoolStatus)
    property_reader = instance_spy(OsCtl::Lib::Zfs::PropertyReader)
    published = []

    allow(NodeCtld::RpcClient).to receive(:run).and_yield(rpc)
    allow(OsCtl::Lib::Zfs::ZpoolStatus).to receive(:new)
      .with(pools: ['tank'])
      .and_return(zpool_status)
    allow(zpool_status).to receive(:[]).with('tank').and_return(
      PoolStatusSpecEntry.new(
        state: :online,
        scan: :none,
        scan_percent: nil
      )
    )
    allow(OsCtl::Lib::Zfs::PropertyReader).to receive(:new).and_return(property_reader)
    allow(property_reader).to receive(:read).and_return(
      'tank/private-a' => PoolStatusSpecFilesystem.new(
        properties: { 'used' => '4096', 'available' => '8192' }
      )
    )
    allow(NodeCtld::NodeBunny).to receive(:publish_drop) do |_exchange, payload, **_opts|
      published << JSON.parse(payload)
    end

    status = described_class.new
    status.init
    status.update

    expect(property_reader).to have_received(:read).with(
      ['tank/private-a'],
      %w[used available]
    )

    expect(published).to include(
      include(
        'id' => 123,
        'state' => 'online',
        'scan' => 'none',
        'used_bytes' => 4096,
        'available_bytes' => 8192,
        'total_bytes' => 12_288
      )
    )
  end
end
