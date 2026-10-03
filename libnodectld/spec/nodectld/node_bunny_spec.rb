# frozen_string_literal: true

require 'spec_helper'
require 'bunny'
require 'nodectld/console'
require 'nodectld/node_bunny'
require 'nodectld/console/server'
require 'nodectld/storage_status'
require 'timeout'

RSpec.describe NodeCtld::NodeBunny do
  let(:connection) do
    Bunny.new(continuation_timeout: 0.05, write_timeout: 0.05).tap do |session|
      session.instance_variable_set(:@transport, transport)
      session.instance_variable_set(:@channel_id_allocator, Bunny::ChannelIdAllocator.new)
      allow(session).to receive_messages(open?: true, connected?: true)
    end
  end
  let(:transport) do
    instance_double(Bunny::Transport).tap do |t|
      allow(t).to receive_messages(host: '127.0.0.1', port: 5672, write_timeout: 0.05, send_frame: nil)
      allow(t).to receive(:write, &:bytesize)
      closed = false
      allow(t).to receive(:closed?) { closed }
      allow(t).to receive(:close) { closed = true }
    end
  end
  let(:node_bunny) do
    described_class.send(:allocate).tap do |instance|
      instance.instance_variable_set(:@connection, connection)
      instance.send(:initialize_synchronization)

      connection.before_recovery_attempt_starts do
        instance.send(:connection_recovery_started)
      end
      connection.after_recovery_completed { instance.send(:connection_recovered) }
    end
  end

  it 'recovers the session and removes a channel whose open timed out' do
    channel_id = nil
    open_ok = AMQ::Protocol::Channel::OpenOk.new(AMQ::Protocol::EMPTY_STRING)

    allow(connection).to receive(:create_channel) do
      channel = Bunny::Channel.new(connection)
      channel_id = channel.number
      connection.open_channel(channel)
    rescue ::Timeout::Error
      connection.handle_frame(channel_id, open_ok)
      raise
    end
    allow(connection).to receive(:close_transport).and_wrap_original do |original|
      original.call
      connection.send(:notify_of_recovery_attempt_start)
      connection.send(:reset_continuations)
      replace_transport
      connection.send(:notify_of_recovery_completion)
    end

    expect { node_bunny.create_channel }.to raise_error(::Timeout::Error)
    expect(connection).to have_received(:close_transport)
    expect(connection.instance_variable_get(:@channels)).to be_empty
    expect(connection.next_channel_id).to eq(channel_id)
    expect { connection.send(:wait_on_continuations) }.to raise_error(::Timeout::Error)
  end

  it 'waits for channel recovery before publishing a required message' do
    exchange = instance_double(Bunny::Exchange)
    allow(exchange).to receive(:publish).and_return(:published)
    node_bunny
    connection.send(:notify_of_recovery_attempt_start)

    started = Queue.new
    publisher = Thread.new do
      started << true
      node_bunny.publish_wait(exchange, 'payload')
    end
    started.pop
    Timeout.timeout(1) { Thread.pass until publisher.status == 'sleep' }

    expect(exchange).not_to have_received(:publish)

    connection.send(:notify_of_recovery_completion)

    expect(Timeout.timeout(1) { publisher.value }).to eq(:published)
    expect(exchange).to have_received(:publish).with('payload').once
  ensure
    publisher&.kill
  end

  it 'waits for channel recovery before publishing console output' do
    exchange = instance_double(Bunny::Exchange)
    allow(exchange).to receive(:publish).and_return(:published)
    allow(described_class).to receive(:instance).and_return(node_bunny)
    server = NodeCtld::Console::Server.allocate
    server.instance_variable_set(:@output_mutex, Mutex.new)
    server.instance_variable_set(:@output_exchange, exchange)
    connection.send(:notify_of_recovery_attempt_start)

    started = Queue.new
    publisher = Thread.new do
      started << true
      server.publish_output('payload', routing_key: 'session')
    end
    started.pop
    Timeout.timeout(1) { Thread.pass until publisher.status == 'sleep' }

    expect(exchange).not_to have_received(:publish)

    connection.send(:notify_of_recovery_completion)

    expect(Timeout.timeout(1) { publisher.value }).to eq(:published)
    expect(exchange).to have_received(:publish).with(
      'payload',
      routing_key: 'session'
    ).once
  ensure
    publisher&.kill
  end

  it 'retains a storage batch beyond the RPC budget until recovery completes' do
    exchange = instance_double(Bunny::Exchange, publish: :published)
    allow(described_class).to receive(:instance).and_return(node_bunny)
    status = NodeCtld::StorageStatus.allocate
    status.instance_variable_set(:@exchange, exchange)
    status.instance_variable_set(:@message_id, 7)
    batch = [{ id: 1, name: 'available', value: 4096, vps_id: 101 }]
    original_batch = batch.map(&:dup)
    clock = 0
    allow(node_bunny).to receive(:monotonic_time) { clock }
    waits = publisher_wait_events
    connection.send(:notify_of_recovery_attempt_start)

    submitter = Thread.new { status.send(:save_properties, Time.at(123), batch) }
    expect(Timeout.timeout(1) { waits.pop }).to equal(submitter)
    clock = described_class::RECOVERY_WAIT + 1
    wake_publisher_waiters
    expect(Timeout.timeout(1) { waits.pop }).to equal(submitter)

    expect(submitter).to be_alive
    expect(exchange).not_to have_received(:publish)
    expect(batch).to eq(original_batch)
    expect(status.instance_variable_get(:@message_id)).to eq(7)

    replace_transport
    connection.send(:notify_of_recovery_completion)
    expect(Timeout.timeout(1) { submitter.value }).to eq(8)
    expect(batch).to be_empty
    expect(status.instance_variable_get(:@message_id)).to eq(8)
    expect(exchange).to have_received(:publish).with(
      { message_id: 7, time: 123, properties: original_batch }.to_json,
      content_type: 'application/json', routing_key: 'storage_statuses'
    ).once
  ensure
    submitter&.kill&.join
  end

  it 'waits beyond the RPC budget for a competing ordinary publisher' do
    entered = Queue.new
    finish = Queue.new
    owner_exchange = instance_double(Bunny::Exchange)
    allow(owner_exchange).to receive(:publish) do
      entered << true
      finish.pop
      :owner_published
    end
    exchange = instance_double(Bunny::Exchange, publish: :published)
    clock = 0
    allow(node_bunny).to receive(:monotonic_time) { clock }
    waits = publisher_wait_events
    owner = Thread.new { node_bunny.publish_wait(owner_exchange, 'owner') }
    Timeout.timeout(1) { entered.pop }
    publisher = Thread.new { node_bunny.publish_wait(exchange, 'waiting') }
    expect(Timeout.timeout(1) { waits.pop }).to equal(publisher)
    clock = described_class::RECOVERY_WAIT + 1
    wake_publisher_waiters
    expect(Timeout.timeout(1) { waits.pop }).to equal(publisher)

    expect(publisher).to be_alive
    expect(exchange).not_to have_received(:publish)
    expect(node_bunny.instance_variable_get(:@publisher_owner)).to equal(owner)
    expect(node_bunny.instance_variable_get(:@publisher_depth)).to eq(1)
    finish << true
    expect(Timeout.timeout(1) { owner.value }).to eq(:owner_published)
    expect(Timeout.timeout(1) { publisher.value }).to eq(:published)
    expect(exchange).to have_received(:publish).with('waiting').once
    expect(node_bunny.instance_variable_get(:@publisher_owner)).to be_nil
  ensure
    owner&.kill&.join
    publisher&.kill&.join
  end

  it 'expires an opted-in RPC gate wait without a stop predicate or publication' do
    exchange = instance_double(Bunny::Exchange, publish: :published)
    clock = 0
    allow(node_bunny).to receive(:monotonic_time) { clock }
    waits = publisher_wait_events
    connection.send(:notify_of_recovery_attempt_start)
    publisher = Thread.new do
      node_bunny.publish_wait(exchange, 'rpc', recovery_timeout: described_class::RECOVERY_WAIT, stopped: nil)
    rescue described_class::RecoveryTimeout => e
      e
    end
    expect(Timeout.timeout(1) { waits.pop }).to equal(publisher)
    clock = described_class::RECOVERY_WAIT + 1
    wake_publisher_waiters

    expect(Timeout.timeout(1) { publisher.value }).to be_a(described_class::RecoveryTimeout)
    expect(exchange).not_to have_received(:publish)
    expect(node_bunny.instance_variable_get(:@connection_recovering)).to be(true)
    expect(node_bunny.instance_variable_get(:@publisher_owner)).to be_nil
    expect(node_bunny.instance_variable_get(:@publisher_depth)).to eq(0)
  ensure
    publisher&.kill&.join
  end

  it 'consumes internal timeout and stop keywords while preserving message properties' do
    exchange = instance_double(Bunny::Exchange, publish: :published)

    expect(node_bunny.publish_wait(
             exchange, 'rpc', recovery_timeout: described_class::RECOVERY_WAIT, stopped: -> { false },
                              persistent: true, routing_key: 'rpc'
           )).to eq(:published)
    expect(exchange).to have_received(:publish).with('rpc', persistent: true, routing_key: 'rpc').once
  end

  it 'times out an RPC waiter without releasing a competing publisher' do
    entered = Queue.new
    finish = Queue.new
    owner_exchange = instance_double(Bunny::Exchange)
    allow(owner_exchange).to receive(:publish) do
      entered << true
      finish.pop
    end
    exchange = instance_double(Bunny::Exchange, publish: :published)
    clock = 0
    allow(node_bunny).to receive(:monotonic_time) { clock }
    waits = publisher_wait_events
    owner = Thread.new { node_bunny.publish_wait(owner_exchange, 'owner') }
    Timeout.timeout(1) { entered.pop }
    publisher = Thread.new do
      node_bunny.publish_wait(exchange, 'rpc', recovery_timeout: described_class::RECOVERY_WAIT)
    rescue described_class::RecoveryTimeout => e
      e
    end
    expect(Timeout.timeout(1) { waits.pop }).to equal(publisher)
    clock = described_class::RECOVERY_WAIT + 1
    wake_publisher_waiters

    expect(Timeout.timeout(1) { publisher.value }).to be_a(described_class::RecoveryTimeout)
    expect(exchange).not_to have_received(:publish)
    expect(node_bunny.instance_variable_get(:@publisher_owner)).to equal(owner)
    expect(node_bunny.instance_variable_get(:@publisher_depth)).to eq(1)
    finish << true
    Timeout.timeout(1) { owner.value }
    expect(node_bunny.instance_variable_get(:@publisher_owner)).to be_nil
  ensure
    publisher&.kill&.join
    owner&.kill&.join
  end

  it 'cancels bounded and unbounded waiters without releasing a competing publisher' do
    entered = Queue.new
    finish = Queue.new
    owner_exchange = instance_double(Bunny::Exchange)
    allow(owner_exchange).to receive(:publish) do
      entered << true
      finish.pop
    end
    exchange = instance_double(Bunny::Exchange, publish: :published)
    waits = publisher_wait_events
    owner = Thread.new { node_bunny.publish_wait(owner_exchange, 'owner') }
    Timeout.timeout(1) { entered.pop }

    publisher = nil
    [nil, described_class::RECOVERY_WAIT].each do |timeout|
      stopped = false
      publisher = Thread.new do
        node_bunny.publish_wait(exchange, 'cancelled', recovery_timeout: timeout, stopped: -> { stopped })
      rescue described_class::Stopped => e
        e
      end
      expect(Timeout.timeout(1) { waits.pop }).to equal(publisher)
      stopped = true
      wake_publisher_waiters
      expect(Timeout.timeout(1) { publisher.value }).to be_a(described_class::Stopped)
      expect(node_bunny.instance_variable_get(:@publisher_owner)).to equal(owner)
      expect(node_bunny.instance_variable_get(:@publisher_depth)).to eq(1)
    end
    expect(exchange).not_to have_received(:publish)
    finish << true
    Timeout.timeout(1) { owner.value }
    expect(node_bunny.instance_variable_get(:@publisher_owner)).to be_nil
  ensure
    publisher&.kill&.join
    owner&.kill&.join
  end

  it 'drops an optional message while channel recovery is in progress' do
    exchange = instance_double(Bunny::Exchange)
    allow(exchange).to receive(:publish)
    node_bunny
    connection.send(:notify_of_recovery_attempt_start)

    expect(node_bunny.publish_drop(exchange, 'payload')).to be(false)
    expect(exchange).not_to have_received(:publish)
  end

  it 'allows a publish write failure to start recovery on the publisher thread' do
    exchange = instance_double(Bunny::Exchange)
    allow(exchange).to receive(:publish) do
      connection.send(:notify_of_recovery_attempt_start)
      raise Bunny::ConnectionClosedError, 'spec frame'
    end

    expect(node_bunny.publish_drop(exchange, 'payload')).to be(false)
    expect(node_bunny.instance_variable_get(:@connection_recovering)).to be(true)
  end

  it 'does not begin channel recovery during an in-flight publish' do
    publish_started = Queue.new
    finish_publish = Queue.new
    exchange = instance_double(Bunny::Exchange)
    allow(exchange).to receive(:publish) do
      publish_started << true
      finish_publish.pop
      :published
    end

    publisher = Thread.new { node_bunny.publish_wait(exchange, 'payload') }
    Timeout.timeout(1) { publish_started.pop }
    recovery = Thread.new { connection.send(:notify_of_recovery_attempt_start) }

    expect(node_bunny.publish_drop(exchange, 'optional')).to be(false)
    expect(recovery).to be_alive

    finish_publish << true
    expect(Timeout.timeout(1) { publisher.value }).to eq(:published)
    Timeout.timeout(1) { recovery.join }
    expect(node_bunny.instance_variable_get(:@connection_recovering)).to be(true)
  ensure
    publisher&.kill
    recovery&.kill
  end

  it 'keeps delete and close continuations isolated until actual transport closure' do
    channel = open_local_channel
    queue = Bunny::Queue.new(channel, 'reply', exclusive: true, no_declare: true)
    node_bunny

    expect { queue.delete }.to raise_error(::Timeout::Error)
    channel.handle_method(AMQ::Protocol::Queue::DeleteOk.new(0))
    entry = node_bunny.send(:register_retirement, channel)
    expect(entry.complete).to be(false)
    expect(connection.next_channel_id).not_to eq(channel.number)
    expect(node_bunny.publish_drop(instance_double(Bunny::Exchange), 'optional')).to be(false)

    connection.handle_frame(channel.number, AMQ::Protocol::Channel::CloseOk.new)
    connection.send(:notify_of_recovery_attempt_start)
    expect(transport).to be_closed
    expect(entry.complete).to be(true)
    expect(connection.instance_variable_get(:@channels)).not_to have_key(channel.number)
    # Reset belongs to Bunny's new connection, never a live old continuation.
    connection.send(:reset_continuations)
    replace_transport
    connection.send(:notify_of_recovery_completion)
    expect(connection.next_channel_id).to eq(channel.number)
    expect { connection.send(:wait_on_continuations) }.to raise_error(::Timeout::Error)
  end

  it 'reaps real workers even after shutdown marks the consumer pool not running' do
    channel = open_local_channel
    survivor = open_local_channel
    pool = channel.instance_variable_get(:@work_pool)
    entered = Queue.new
    pool.start
    pool.submit do
      entered << true
      Queue.new.pop
    end
    Timeout.timeout(1) { entered.pop }
    pool.shutdown
    expect(pool).not_to be_running
    expect(pool.threads.first).to be_alive
    queue = Bunny::Queue.new(channel, 'reply', no_declare: true)
    consumer = Bunny::Consumer.new(channel, queue, 'reply-consumer')
    channel.register_consumer('reply-consumer', consumer)
    allow(consumer).to receive(:recover_from_network_failure).and_call_original
    allow(survivor).to receive(:open).and_return(survivor)
    allow(survivor).to receive(:recover_from_network_failure).and_call_original

    node_bunny.send(:register_retirement, channel)
    connection.send(:notify_of_recovery_attempt_start)
    expect(pool.threads).to all(satisfy { |thread| !thread.alive? })
    expect(connection.instance_variable_get(:@channels).values).to eq([survivor])
    expect(channel.instance_variable_get(:@nodectld_retirement).complete).to be(true)
    replace_transport
    connection.send(:recover_channels)
    expect(survivor).to have_received(:recover_from_network_failure).once
    expect(consumer).not_to have_received(:recover_from_network_failure)
  ensure
    pool&.kill
    pool&.threads&.each(&:join)
  end

  it 'coalesces concurrent retirement requests and completed tokens do no more I/O' do
    channel = open_local_channel
    started = Queue.new
    node_bunny
    threads = Array.new(2) do
      Thread.new do
        started << true
        node_bunny.retire_channel(channel)
      end
    end
    2.times { Timeout.timeout(1) { started.pop } }
    Timeout.timeout(1) { Thread.pass until node_bunny.instance_variable_get(:@retirements).length == 1 && transport.closed? }
    connection.send(:notify_of_recovery_attempt_start)
    replace_transport
    connection.send(:notify_of_recovery_completion)

    entries = threads.map { |thread| Timeout.timeout(1) { thread.value } }
    expect(entries.first).to equal(entries.last)
    expect(node_bunny.retire_channel(channel)).to equal(entries.first)
    expect(transport).to have_received(:close).once
    expect(node_bunny.instance_variable_get(:@retirements)).to be_empty
  ensure
    threads&.each { |thread| thread.kill.join }
  end

  it 'does not acknowledge a late retirement with an unrelated recovery generation' do
    channel = open_local_channel
    node_bunny
    connection.send(:notify_of_recovery_attempt_start)
    replace_transport
    entry = node_bunny.send(:register_retirement, channel)
    # This channel missed the before hook and would already be a survivor.
    connection.send(:notify_of_recovery_completion)

    expect(entry.complete).to be(false)
    expect(connection.transport).to be_closed
    expect(node_bunny.instance_variable_get(:@connection_recovering)).to be(true)
    expect(connection.instance_variable_get(:@channels)).to have_key(channel.number)
    connection.send(:notify_of_recovery_attempt_start)
    expect(entry.complete).to be(true)
    replace_transport
    connection.send(:notify_of_recovery_completion)
    expect(node_bunny.instance_variable_get(:@connection_recovering)).to be(false)
  end

  it 'drains a second retirement registered while the first pending batch is reaped' do
    first = open_local_channel
    second = open_local_channel
    node_bunny.send(:register_retirement, first)
    allow(connection).to receive(:unregister_channel).and_wrap_original do |original, channel|
      node_bunny.send(:register_retirement, second) if channel.equal?(first)
      original.call(channel)
    end

    connection.send(:notify_of_recovery_attempt_start)
    expect(connection.instance_variable_get(:@channels)).to be_empty
    expect(second.instance_variable_get(:@nodectld_retirement).complete).to be(true)
  end

  it 'leaves a retirement pending if Bunny swallows a failed transport close' do
    channel = open_local_channel
    allow(transport).to receive(:close).and_raise(IOError, 'fixture close failed')

    expect { node_bunny.retire_channel(channel) }.to raise_error(described_class::RecoveryFailed)
    expect(channel.instance_variable_get(:@nodectld_retirement).complete).to be(false)
    expect(connection.instance_variable_get(:@channels)).to have_key(channel.number)
    expect(node_bunny.instance_variable_get(:@connection_recovering)).to be(true)
  end

  it 'bounds recovery waiting and cooperative stop without releasing pending channels' do
    channel = open_local_channel
    stub_const("#{described_class}::RECOVERY_WAIT", 0.02)

    expect { node_bunny.retire_channel(channel) }.to raise_error(described_class::RecoveryTimeout)
    expect { node_bunny.create_channel(stopped: -> { true }) }.to raise_error(described_class::Stopped)
    expect(channel.instance_variable_get(:@nodectld_retirement).complete).to be(false)
    expect(connection.instance_variable_get(:@channels)).to have_key(channel.number)
  end

  it 'waits for complete survivor recovery before admitting channel creation' do
    node_bunny
    connection.send(:notify_of_recovery_attempt_start)
    allow(connection).to receive(:create_channel).and_return(:created)
    creator = Thread.new { node_bunny.create_channel }
    Timeout.timeout(1) { Thread.pass until creator.status == 'sleep' }
    expect(connection).not_to have_received(:create_channel)

    replace_transport
    connection.send(:notify_of_recovery_completion)
    expect(Timeout.timeout(1) { creator.value }).to eq(:created)
  ensure
    creator&.kill&.join
  end

  it 'retire channels from the old reader recovery boundary without joining itself' do
    channel = open_local_channel
    reader = Bunny::ReaderLoop.new(transport, connection, Thread.current)
    connection.instance_variable_set(:@reader_loop, reader)
    node_bunny.send(:register_retirement, channel)
    thread = Thread.new do
      reader.instance_variable_set(:@thread, Thread.current)
      reader.instance_variable_set(:@network_is_down, true)
      connection.send(:notify_of_recovery_attempt_start)
    end

    Timeout.timeout(1) { thread.value }
    expect(channel.instance_variable_get(:@nodectld_retirement).complete).to be(true)
    expect(reader).to be_stopping
  ensure
    thread&.kill&.join
  end

  it 'joins the old reader when recovery runs synchronously on a publisher' do
    channel = open_local_channel
    reader = Bunny::ReaderLoop.new(transport, connection, Thread.current)
    reader_thread = Thread.new { Thread.pass until reader.stopping? }
    reader.instance_variable_set(:@thread, reader_thread)
    connection.instance_variable_set(:@reader_loop, reader)
    exchange = instance_double(Bunny::Exchange)
    allow(exchange).to receive(:publish) do
      node_bunny.send(:register_retirement, channel)
      connection.send(:notify_of_recovery_attempt_start)
      replace_transport
      connection.instance_variable_set(:@reader_loop, nil)
      connection.send(:notify_of_recovery_completion)
      :published
    end

    expect(node_bunny.publish_wait(exchange, 'payload')).to eq(:published)
    expect(reader_thread).not_to be_alive
    expect(channel.instance_variable_get(:@nodectld_retirement).complete).to be(true)
  ensure
    reader_thread&.kill&.join
  end

  def open_local_channel
    Bunny::Channel.new(connection).tap { |channel| channel.instance_variable_set(:@status, :open) }
  end

  def publisher_wait_events
    events = Queue.new
    condition = node_bunny.instance_variable_get(:@connection_recovery_condition)
    allow(condition).to receive(:wait).and_wrap_original do |original, *args|
      events << Thread.current
      original.call(*args)
    end
    events
  end

  def wake_publisher_waiters
    node_bunny.instance_variable_get(:@connection_recovery_mutex).synchronize do
      node_bunny.instance_variable_get(:@connection_recovery_condition).broadcast
    end
  end

  def replace_transport
    closed = false
    replacement = instance_double(Bunny::Transport)
    allow(replacement).to receive_messages(host: '127.0.0.1', port: 5672, write_timeout: 0.05, send_frame: nil)
    allow(replacement).to receive(:closed?) { closed }
    allow(replacement).to receive(:close) { closed = true }
    allow(replacement).to receive(:write, &:bytesize)
    connection.instance_variable_set(:@transport, replacement)
  end
end
