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
    allow(NodeCtld::NodeBunny).to receive(:exchange_name).and_return('node:test')
    allow(channel).to receive(:direct).with('node:test').and_return(exchange)
    allow(channel).to receive(:queue).with('', exclusive: true).and_return(reply_queue)
    allow(reply_queue).to receive(:bind).with(exchange, routing_key: '')
    allow(reply_queue).to receive(:subscribe)
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
    rescue ::Timeout::Error
      timed_out = true
    end

    expect(timed_out).to be(true)
    expect(NodeCtld::NodeBunny).to have_received(:create_channel)
      .exactly(described_class::SETUP_RETRIES + 1).times
  end
end
