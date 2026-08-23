# frozen_string_literal: true

require 'spec_helper'
require 'bunny'
require 'nodectld/console'
require 'nodectld/node_bunny'
require 'nodectld/console/server'
require 'timeout'

RSpec.describe NodeCtld::NodeBunny do
  let(:connection) do
    Bunny.new(continuation_timeout: 1).tap do |session|
      session.instance_variable_set(:@transport, transport)
      session.instance_variable_set(:@channel_id_allocator, Bunny::ChannelIdAllocator.new)
      allow(session).to receive(:open?).and_return(true)
    end
  end
  let(:transport) do
    instance_double(Bunny::Transport).tap do |t|
      allow(t).to receive(:send_frame)
    end
  end
  let(:node_bunny) do
    described_class.send(:allocate).tap do |instance|
      instance.instance_variable_set(:@connection, connection)
      instance.instance_variable_set(:@channel_creation_mutex, Mutex.new)
      monitor = Monitor.new
      instance.instance_variable_set(:@connection_recovery_mutex, monitor)
      instance.instance_variable_set(:@connection_recovery_condition, monitor.new_cond)
      instance.instance_variable_set(:@connection_recovery_generation, 0)
      instance.instance_variable_set(:@connection_recovering, false)
      instance.instance_variable_set(:@timed_out_channels, [])

      connection.before_recovery_attempt_starts do
        instance.send(:connection_recovery_started)
      end
      connection.after_recovery_completed { instance.send(:connection_recovered) }
    end
  end

  it 'recovers the session and removes a channel whose open timed out' do
    channel_id = connection.next_channel_id
    channel = instance_double(Bunny::Channel, number: channel_id)
    open_ok = AMQ::Protocol::Channel::OpenOk.new(AMQ::Protocol::EMPTY_STRING)

    allow(connection).to receive(:create_channel) do
      connection.open_channel(channel)
    rescue ::Timeout::Error
      connection.handle_frame(channel_id, open_ok)
      raise
    end
    allow(connection).to receive(:close_transport) do
      connection.send(:notify_of_recovery_attempt_start)
      connection.send(:reset_continuations)
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
end
