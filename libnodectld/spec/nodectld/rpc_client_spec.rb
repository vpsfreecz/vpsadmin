# frozen_string_literal: true

require 'spec_helper'
require 'bunny'
require 'nodectld/rpc_client'

RSpec.describe NodeCtld::RpcClient do
  let(:channel) { instance_double(Bunny::Channel) }
  let(:exchange) { instance_double(Bunny::Exchange) }
  let(:reply_queue) { instance_double(Bunny::Queue, name: '') }

  before do
    stub_const("#{described_class}::SETUP_RETRY_DELAY", 0)
    $CFG.patch(rpc_client: { debug: false })
    allow(NodeCtld::NodeBunny).to receive(:channel_lifecycle) { |**_options, &block| block.call }
    allow(NodeCtld::NodeBunny).to receive(:retire_channel)
    allow(NodeCtld::NodeBunny).to receive_messages(create_channel: channel, exchange_name: 'node:test')
    allow(channel).to receive(:direct).with('node:test').and_return(exchange)
    allow(channel).to receive(:queue).with('', exclusive: true).and_return(reply_queue)
    allow(reply_queue).to receive(:bind).with(exchange, routing_key: '')
    allow(reply_queue).to receive(:subscribe)
    allow(reply_queue).to receive(:delete)
    allow(channel).to receive(:close)
  end

  it 'retries channel creation after it times out' do
    calls = 0

    allow(NodeCtld::NodeBunny).to receive(:create_channel) do
      calls += 1
      raise ::Timeout::Error if calls == 1

      channel
    end

    described_class.new

    expect(NodeCtld::NodeBunny).to have_received(:create_channel).twice
    expect(channel).to have_received(:direct).with('node:test')
    expect(reply_queue).to have_received(:subscribe)
  end

  it 'uses a new channel after an exchange declaration times out' do
    timed_out_channel = instance_double(Bunny::Channel)

    allow(timed_out_channel).to receive(:direct).and_raise(::Timeout::Error)
    allow(timed_out_channel).to receive(:queue)
    allow(NodeCtld::NodeBunny).to receive(:create_channel).and_return(timed_out_channel, channel)

    described_class.new

    expect(NodeCtld::NodeBunny).to have_received(:create_channel).twice
    expect(timed_out_channel).not_to have_received(:queue)
    expect(NodeCtld::NodeBunny).to have_received(:retire_channel).with(timed_out_channel, stopped: nil).once
    expect(channel).to have_received(:queue).with('', exclusive: true)
    expect(reply_queue).to have_received(:subscribe)
  end

  it 'uses a new channel after reply queue declaration times out' do
    timed_out_channel = instance_double(Bunny::Channel)
    timed_out_exchange = instance_double(Bunny::Exchange)

    allow(timed_out_channel).to receive(:direct).with('node:test').and_return(timed_out_exchange)
    allow(timed_out_channel).to receive(:queue).and_raise(::Timeout::Error)
    allow(NodeCtld::NodeBunny).to receive(:create_channel).and_return(timed_out_channel, channel)

    described_class.new

    expect(NodeCtld::NodeBunny).to have_received(:create_channel).twice
    expect(timed_out_channel).to have_received(:queue).with('', exclusive: true)
    expect(channel).to have_received(:queue).with('', exclusive: true)
    expect(reply_queue).to have_received(:subscribe)
  end

  it 'uses a new channel after reply queue binding times out' do
    timed_out_channel = instance_double(Bunny::Channel)
    timed_out_exchange = instance_double(Bunny::Exchange)
    timed_out_queue = instance_double(Bunny::Queue, name: '')

    allow(timed_out_channel).to receive(:direct).with('node:test').and_return(timed_out_exchange)
    allow(timed_out_channel).to receive(:queue).with('', exclusive: true).and_return(timed_out_queue)
    allow(timed_out_queue).to receive(:bind).and_raise(::Timeout::Error)
    allow(NodeCtld::NodeBunny).to receive(:create_channel).and_return(timed_out_channel, channel)

    described_class.new

    expect(NodeCtld::NodeBunny).to have_received(:create_channel).twice
    expect(timed_out_queue).to have_received(:bind).with(timed_out_exchange, routing_key: '')
    expect(reply_queue).to have_received(:bind).with(exchange, routing_key: '')
    expect(reply_queue).to have_received(:subscribe)
  end

  it 'uses a new channel after reply queue subscription times out' do
    timed_out_channel = instance_double(Bunny::Channel)
    timed_out_exchange = instance_double(Bunny::Exchange)
    timed_out_queue = instance_double(Bunny::Queue, name: '')

    allow(timed_out_channel).to receive(:direct).with('node:test').and_return(timed_out_exchange)
    allow(timed_out_channel).to receive(:queue).with('', exclusive: true).and_return(timed_out_queue)
    allow(timed_out_queue).to receive(:bind).with(timed_out_exchange, routing_key: '')
    allow(timed_out_queue).to receive(:subscribe).and_raise(::Timeout::Error)
    allow(NodeCtld::NodeBunny).to receive(:create_channel).and_return(timed_out_channel, channel)

    described_class.new

    expect(NodeCtld::NodeBunny).to have_received(:create_channel).twice
    expect(timed_out_queue).to have_received(:subscribe)
    expect(reply_queue).to have_received(:subscribe)
  end

  it 'makes a final setup attempt after exhausting delayed retries' do
    allow(NodeCtld::NodeBunny).to receive(:create_channel).and_raise(::Timeout::Error)

    timed_out = false

    begin
      described_class.new
    rescue described_class::TransportError => e
      timed_out = true
      expect(e.cause).to be_a(::Timeout::Error)
    end

    expect(timed_out).to be(true)
    expect(NodeCtld::NodeBunny).to have_received(:create_channel)
      .exactly(described_class::SETUP_RETRIES + 1).times
  end

  it 'preserves successful values and nonlocal return through cleanup' do
    value = Object.new
    expect(described_class.run { value }).to equal(value)
    expect(return_from_rpc).to eq(:returned)
    expect(reply_queue).to have_received(:delete).twice
  end

  it 'preserves the original exception object and backtrace over cleanup timeout' do
    original = described_class::Timeout.new('body failed')
    original.set_backtrace(['public-body.rb:12'])
    allow(reply_queue).to receive(:delete).and_raise(::Timeout::Error)

    expect { described_class.run { raise original } }.to raise_error do |error|
      expect(error).to equal(original)
      expect(error.backtrace).to eq(['public-body.rb:12'])
    end
    expect(channel).not_to have_received(:close)
    expect(NodeCtld::NodeBunny).to have_received(:retire_channel).once
  end

  it 'reports cleanup-only timeout with its cause and performs no later broker I/O' do
    original = ::Timeout::Error.new('delete failed')
    allow(reply_queue).to receive(:delete).and_raise(original)
    rpc = described_class.new

    expect { rpc.close }.to raise_error(described_class::CleanupError) do |error|
      expect(error.cause).to equal(original)
    end
    expect(rpc.close).to be_nil
    expect { rpc.list_pools }.to raise_error(described_class::Error, /closed/)
    expect(reply_queue).to have_received(:delete).once
    expect(channel).not_to have_received(:close)
    expect(NodeCtld::NodeBunny).to have_received(:retire_channel).once
  end

  it 'serializes concurrent close callers and closes a healthy channel once' do
    rpc = described_class.new
    threads = Array.new(3) { Thread.new { rpc.close } }
    threads.each(&:value)

    expect(reply_queue).to have_received(:delete).once
    expect(channel).to have_received(:close).once
    expect(NodeCtld::NodeBunny).not_to have_received(:retire_channel)
  ensure
    threads&.each { |thread| thread.kill.join }
  end

  it 'keeps a close timeout distinct from a successful request body' do
    allow(channel).to receive(:close).and_raise(::Timeout::Error)

    expect { described_class.run { :success } }.to raise_error(described_class::CleanupError)
    expect(reply_queue).to have_received(:delete).once
    expect(NodeCtld::NodeBunny).to have_received(:retire_channel).with(channel, stopped: nil).once
  end

  it 'propagates unexpected cleanup errors and preserves a pending Interrupt' do
    programming_error = NameError.new('fixture programming error')
    allow(reply_queue).to receive(:delete).and_raise(programming_error)

    expect { described_class.run { :success } }.to(raise_error { |error| expect(error).to equal(programming_error) })
    original = Interrupt.new('fixture interrupt')
    expect { described_class.run { raise original } }.to(raise_error { |error| expect(error).to equal(original) })
  end

  it 'retires the final partial constructor as well as the retried ones' do
    stub_const("#{described_class}::SETUP_RETRIES", 1)
    allow(reply_queue).to receive(:subscribe).and_raise(::Timeout::Error)

    expect { described_class.new }.to raise_error(described_class::TransportError)
    expect(NodeCtld::NodeBunny).to have_received(:retire_channel).with(channel, stopped: nil).twice
  end

  it 'retires a partial constructor on programming failure without normalizing it' do
    original = NoMethodError.new('fixture programming error')
    allow(reply_queue).to receive(:bind).and_raise(original)

    expect { described_class.new }.to(raise_error { |error| expect(error).to equal(original) })
    expect(NodeCtld::NodeBunny).to have_received(:retire_channel).once
    expect(reply_queue).not_to have_received(:subscribe)
  end

  it 'checks cooperative stop during setup backoff and leaves safe retirement owned' do
    stopped = false
    allow(channel).to receive(:direct).and_raise(::Timeout::Error)
    allow(NodeCtld::NodeBunny).to receive(:retire_channel) { stopped = true }

    expect { described_class.new(stopped: -> { stopped }) }.to raise_error(described_class::Stopped)
    expect(NodeCtld::NodeBunny).to have_received(:create_channel).once
    expect(NodeCtld::NodeBunny).to have_received(:retire_channel).once
  end

  it 'does not hide programming or permanent broker errors in network wrappers' do
    original = NameError.new('fixture programming error')
    wrapped = Bunny::NetworkErrorWrapper.new(original)
    allow(reply_queue).to receive(:delete).and_raise(wrapped)

    expect { described_class.run { :success } }.to(raise_error { |error| expect(error).to equal(wrapped) })
    permanent = Bunny::AccessRefused.new('fixture refused', channel, nil)
    channel.instance_variable_set(:@last_channel_error, permanent)
    closed = Bunny::ChannelAlreadyClosed.new('fixture closed', channel)
    allow(reply_queue).to receive(:delete).and_raise(closed)

    expect { described_class.run { :success } }.to(raise_error { |error| expect(error).to equal(closed) })
  end

  it 'reports cleanup-only timeout inside an enclosing rescue with its exact cause' do
    cleanup = ::Timeout::Error.new('fixture cleanup timeout')
    allow(reply_queue).to receive(:delete).and_raise(cleanup)

    expect { inside_outer_rescue { described_class.run { :success } } }
      .to raise_error(described_class::CleanupError) { |error| expect(error.cause).to equal(cleanup) }
  end

  it 'propagates unexpected cleanup errors inside an enclosing rescue' do
    cleanup = NameError.new('fixture cleanup programming failure')
    allow(reply_queue).to receive(:delete).and_raise(cleanup)

    expect { inside_outer_rescue { described_class.run { :success } } }
      .to(raise_error { |error| expect(error).to equal(cleanup) })
  end

  it 'propagates cleanup signals inside an enclosing rescue' do
    [Interrupt.new('fixture interrupt'), SystemExit.new(17)].each do |cleanup|
      allow(reply_queue).to receive(:delete).and_raise(cleanup)

      expect { inside_outer_rescue { described_class.run { :success } } }
        .to(raise_error { |error| expect(error).to equal(cleanup) })
    end
  end

  it 'preserves successful values and nonlocal return and break inside an enclosing rescue' do
    value = Object.new

    expect(inside_outer_rescue { described_class.run { value } }).to equal(value)
    expect(return_from_rpc_in_rescue).to eq(:returned)
    expect(inside_outer_rescue { described_class.run { break :broken } }).to eq(:broken)
    expect(reply_queue).to have_received(:delete).exactly(3).times
    expect(channel).to have_received(:close).exactly(3).times
  end

  it 'lets cleanup-only failure interrupt nonlocal return and break inside an enclosing rescue' do
    cleanup = ::Timeout::Error.new('fixture cleanup timeout')
    allow(reply_queue).to receive(:delete).and_raise(cleanup)

    expect { return_from_rpc_in_rescue }.to raise_error(described_class::CleanupError) do |error|
      expect(error.cause).to equal(cleanup)
    end
    expect { inside_outer_rescue { described_class.run { break :broken } } }
      .to raise_error(described_class::CleanupError) { |error| expect(error.cause).to equal(cleanup) }
  end

  it 'preserves the same enclosing exception when the body explicitly raises it again' do
    original = RuntimeError.new('fixture outer exception')
    original.set_backtrace(['public-outer.rb:12'])
    allow(reply_queue).to receive(:delete).and_raise(::Timeout::Error)

    expect { inside_outer_rescue(original) { |outer| described_class.run { raise outer } } }.to raise_error do |error|
      expect(error).to equal(original)
      expect(error.backtrace).to eq(['public-outer.rb:12'])
    end
  end

  it 'preserves local body signals over secondary cleanup inside an enclosing rescue' do
    allow(reply_queue).to receive(:delete).and_raise(::Timeout::Error)

    [Interrupt.new('fixture interrupt'), SystemExit.new(17)].each do |original|
      original.set_backtrace(['public-body.rb:34'])
      expect { inside_outer_rescue { described_class.run { raise original } } }.to raise_error do |error|
        expect(error).to equal(original)
        expect(error.backtrace).to eq(['public-body.rb:34'])
      end
    end
  end

  it 'preserves constructor failure inside an enclosing rescue without yielding or closing again' do
    original = Interrupt.new('fixture constructor interrupt')
    original.set_backtrace(['public-constructor.rb:56'])
    allow(reply_queue).to receive(:bind).and_raise(original)
    yielded = false

    expect { inside_outer_rescue { described_class.run { yielded = true } } }.to raise_error do |error|
      expect(error).to equal(original)
      expect(error.backtrace).to eq(['public-constructor.rb:56'])
    end
    expect(yielded).to be(false)
    expect(reply_queue).not_to have_received(:delete)
    expect(channel).not_to have_received(:close)
    expect(NodeCtld::NodeBunny).to have_received(:retire_channel).once
  end

  it 'preserves a local body failure even when its cleanup diagnostic also fails' do
    rpc = described_class.new
    original = NameError.new('fixture body programming failure')
    original.set_backtrace(['public-body.rb:78'])
    allow(described_class).to receive(:new).and_return(rpc)
    allow(reply_queue).to receive(:delete).and_raise(::Timeout::Error)
    allow(rpc).to receive(:log).and_raise(Interrupt, 'fixture diagnostic interrupt')

    expect { inside_outer_rescue { described_class.run { raise original } } }.to raise_error do |error|
      expect(error).to equal(original)
      expect(error.backtrace).to eq(['public-body.rb:78'])
    end
  end

  it 'explicitly bounds RPC publication even without a cooperative stop predicate' do
    rpc = described_class.new
    allow(NodeCtld::NodeBunny).to receive(:publish_wait) do
      rpc.send(:response=, { 'status' => true, 'response' => [] })
    end

    expect(rpc.list_pools).to eq([])
    expect(NodeCtld::NodeBunny).to have_received(:publish_wait).with(
      exchange, anything,
      persistent: true, content_type: 'application/json', routing_key: 'rpc',
      correlation_id: anything, reply_to: '', stopped: nil,
      recovery_timeout: NodeCtld::NodeBunny::RECOVERY_WAIT
    ).once
    rpc.close
  end

  def return_from_rpc
    described_class.run { return :returned }
  end

  def inside_outer_rescue(original = RuntimeError.new('fixture outer exception'))
    raise original
  rescue RuntimeError => e
    yield e
  end

  def return_from_rpc_in_rescue
    inside_outer_rescue do
      described_class.run { return :returned }
    end
  end
end
