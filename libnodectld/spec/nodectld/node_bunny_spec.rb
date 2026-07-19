# frozen_string_literal: true

require 'spec_helper'
require 'bunny'
require 'nodectld/node_bunny'

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
      instance.instance_variable_set(:@connection_recovery_mutex, Mutex.new)
      instance.instance_variable_set(:@connection_recovery_condition, ConditionVariable.new)
      instance.instance_variable_set(:@connection_recovery_generation, 0)
      instance.instance_variable_set(:@timed_out_channels, [])

      connection.before_recovery_attempt_starts do
        instance.send(:remove_timed_out_channels)
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
end
