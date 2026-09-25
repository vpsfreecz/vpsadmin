# frozen_string_literal: true

require 'spec_helper'
require 'bunny'
require 'nodectld/storage_inventory'
require 'nodectld/transaction_verifier'
require 'rbconfig'

RSpec.describe NodeCtld::StorageInventory do
  let(:deadline) { Time.now.utc + 0.5 }
  let(:request) do
    Struct.new(:deadline, :zpool, :routing_key)
          .new(deadline, 'tank', 'storage_inventory:test')
  end

  it 'registers handle 5290 through the normal NodeCtld command loader' do
    require 'nodectld'

    handlers = NodeCtld::Command.class_variable_get(:@@handlers)
    expect(handlers.fetch(5290)).to eq('NodeCtld::Commands::Storage::Inventory')
  end

  it 'rejects an unsigned inventory request before catalog access' do
    command = Struct.new(:trans).new({ 'signature' => nil, 'handle' => 5290 })
    signed_request = described_class::Request.new(command, {}, now: -> { Time.now.utc })

    expect { signed_request.validate! }
      .to raise_error(described_class::Invalid, 'inventory command is unsigned')
  end

  it 'rejects a mismatched signed handle before catalog access' do
    command = Struct.new(:trans).new({
      'signature' => 'signed', 'input' => '{}', 'handle' => 5204
    })
    allow(NodeCtld::TransactionVerifier).to receive(:verify_base64).and_return(true)
    signed_request = described_class::Request.new(command, {}, now: -> { Time.now.utc })

    expect { signed_request.validate! }
      .to raise_error(described_class::Invalid, 'wrong inventory handle')
  end

  it 'validates a signed bounded request and refuses a different return route' do
    run_uuid = SecureRandom.uuid
    params = {
      protocol_version: 1, run_uuid:, attempt_uuid: SecureRandom.uuid,
      node_id: 1, pool_id: 2, zpool: 'tank', zpool_guid: '123',
      managed_root: 'tank/backup', roots: ['tank/backup'],
      routing_key: "storage_inventory:#{run_uuid}", nonce: 'a' * 64,
      deadline: (Time.now.utc + 60).iso8601(6)
    }
    command = Struct.new(:trans).new({
      'signature' => 'signed', 'input' => 'signed-input',
      'handle' => 5290, 'node_id' => 1
    })
    allow(NodeCtld::TransactionVerifier).to receive(:verify_base64)
      .with('signed-input', 'signed').and_return(true)
    previous_cfg = $CFG
    $CFG = Struct.new(:node_id) do
      def get(*)
        node_id
      end
    end.new(1)
    valid = described_class::Request.new(command, params, now: -> { Time.now.utc })
    allow(valid).to receive(:check_catalog!)
    expect(valid.validate!).to equal(valid)

    wrong_route = described_class::Request.new(
      command, params.merge(routing_key: 'storage_inventory:other'),
      now: -> { Time.now.utc }
    )
    expect { wrong_route.validate! }
      .to raise_error(described_class::Invalid, 'invalid inventory scope')
  ensure
    $CFG = previous_cfg
  end

  it 'terminates and reaps a silent inventory child at the signed deadline' do
    request.deadline = Time.now.utc + 5
    scanner = described_class::Scanner.new(nil, request, now: -> { Time.now.utc })
    child_pid = nil
    allow(Open3).to receive(:popen3).and_wrap_original do |original, *args, &block|
      original.call(*args) do |input, output, stderr, wait|
        child_pid = wait.pid
        block.call(input, output, stderr, wait)
      end
    end
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    command = [RbConfig.ruby, '-e', 'sleep 30']

    expect do
      scanner.send(:each_process_line, command) { |line| raise "unexpected output: #{line}" }
    end.to raise_error(described_class::Invalid, 'inventory subprocess deadline elapsed')

    expect(child_pid).to be_a(Integer)
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 12
    expect { Process.kill(0, child_pid) }.to raise_error(Errno::ESRCH)
  end

  it 'bounds a silent broker publisher confirmation' do
    publisher = described_class::Publisher.allocate
    publisher.instance_variable_set(:@request, request)
    exchange = instance_double(Bunny::Exchange)
    channel = instance_double(Bunny::Channel)
    allow(exchange).to receive(:publish)
    allow(channel).to receive(:wait_for_confirms) { sleep 30 }
    allow(publisher).to receive(:close)
    allow(publisher).to receive(:open_channel!)
    publisher.instance_variable_set(:@exchange, exchange)
    publisher.instance_variable_set(:@channel, channel)

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect { publisher.publish('sealed-frame') }
      .to raise_error(described_class::Invalid, /deadline elapsed|publish failed/)
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 3
    expect(exchange).to have_received(:publish).with(
      'sealed-frame', routing_key: 'storage_inventory:test', persistent: true,
                      mandatory: true, content_type: 'application/json'
    )
  end

  it 'retries an ambiguously confirmed publish with identical bytes' do
    request.deadline = Time.now.utc + 10
    publisher = described_class::Publisher.allocate
    publisher.instance_variable_set(:@request, request)
    payloads = []
    exchange = instance_double(Bunny::Exchange)
    channel = instance_double(Bunny::Channel)
    allow(exchange).to receive(:publish) { |payload, **_options| payloads << payload }
    allow(channel).to receive(:wait_for_confirms).and_return(false, true)
    allow(publisher).to receive(:close)
    allow(publisher).to receive(:open_channel!)
    publisher.instance_variable_set(:@exchange, exchange)
    publisher.instance_variable_set(:@channel, channel)

    expect(publisher.publish('immutable-frame')).to be_nil
    expect(payloads).to eq(%w[immutable-frame immutable-frame])
  end

  it 'accepts a simulated scan longer than thirty minutes within the signed deadline' do
    started = Time.now.utc
    ticks = 0
    clock = lambda do
      ticks += 1
      started + (if ticks > 6
                   32 * 60
                 else
                   ticks > 2 ? 31 * 60 : 0
                 end)
    end
    full_request = instance_double(
      described_class::Request, deadline: started + (2 * 60 * 60), zpool_guid: nil,
                                roots: ['tank/backup'], run_uuid: SecureRandom.uuid,
                                attempt_uuid: SecureRandom.uuid, node_id: 1, pool_id: 2,
                                zpool: 'tank', managed_root: 'tank/backup', nonce: 'a' * 64
    )
    scanner = instance_double(described_class::Scanner, zpool_guid: '123')
    allow(scanner).to receive(:each_record).and_yield({ 'path' => 'tank/backup', 'type' => 'filesystem', 'guid' => '456' })
    published = []
    publisher = instance_double(described_class::Publisher)
    allow(publisher).to receive(:publish) { |payload| published << JSON.parse(payload) }

    result = described_class.new(full_request, scanner, publisher, now: clock).run!

    expect(result.fetch(:object_count)).to eq(1)
    expect(published.map { |frame| frame.fetch('type') }).to eq(%w[chunk final])
    expect(published.last.fetch('first').fetch('observed_until_at')).to be <
                                                                        published.last.fetch('second').fetch('observed_until_at')
  end
end
