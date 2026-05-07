# frozen_string_literal: true

require 'spec_helper'

RpcFakeProperties = Struct.new(:correlation_id, :reply_to)

class RpcFakeConnection
  attr_reader :channel

  def initialize(response_payload:)
    @channel = RpcFakeChannel.new(response_payload: response_payload)
  end

  def create_channel
    channel
  end
end

class RpcFakeChannel
  attr_reader :closed, :queues

  def initialize(response_payload:)
    @queues = {}
    @response_payload = response_payload
    @closed = false
  end

  def direct(name)
    @direct ||= RpcFakeExchange.new(name, self, @response_payload)
  end

  def queue(name = '', **_opts)
    queue_name = name.empty? ? 'reply-queue' : name
    @queues[queue_name] ||= RpcFakeQueue.new(queue_name)
  end

  def close
    @closed = true
  end

  def closed?
    @closed
  end

  def exchange
    @direct
  end
end

class RpcFakeExchange
  attr_reader :name, :published

  def initialize(name, channel, response_payload)
    @name = name
    @channel = channel
    @response_payload = response_payload
    @published = []
  end

  def publish(payload, **opts)
    @published << { payload: payload, opts: opts }
    reply_to = opts.fetch(:reply_to)
    correlation_id = opts.fetch(:correlation_id)
    queue = @channel.queues.fetch(reply_to)

    Thread.new do
      sleep 0.001
      queue.deliver(
        RpcFakeProperties.new('unrelated', nil),
        JSON.dump(status: true, response: 'ignored')
      )
      queue.deliver(
        RpcFakeProperties.new(correlation_id, nil),
        JSON.dump(@response_payload)
      )
    end
  end
end

class RpcFakeQueue
  attr_reader :bindings, :deleted, :name

  def initialize(name)
    @name = name
    @bindings = []
    @deleted = false
  end

  def bind(exchange, routing_key:)
    @bindings << { exchange: exchange, routing_key: routing_key }
  end

  def subscribe(&block)
    @subscriber = block
  end

  def deliver(properties, payload)
    @subscriber.call(nil, properties, payload)
  end

  def delete
    @deleted = true
  end

  def deleted?
    @deleted
  end
end

RSpec.describe VpsAdmin::ConsoleRouter::RpcClient do
  def build_client(response_payload)
    connection = RpcFakeConnection.new(response_payload: response_payload)
    [described_class.new(connection.channel), connection]
  end

  it 'publishes request metadata and returns successful responses' do
    client, connection = build_client(status: true, response: 'http://api.example.test')

    expect(client.get_api_url).to eq('http://api.example.test')

    published = connection.channel.exchange.published.fetch(0)
    payload = JSON.parse(published.fetch(:payload))
    opts = published.fetch(:opts)

    expect(payload).to eq(
      'command' => 'get_api_url',
      'args' => [],
      'kwargs' => {}
    )
    expect(opts).to include(
      persistent: true,
      content_type: 'application/json',
      routing_key: 'rpc',
      reply_to: 'reply-queue'
    )
    expect(opts.fetch(:correlation_id)).to match(/\A\h{40}\z/)
  ensure
    client&.close
  end

  it 'passes session lookup arguments' do
    client, connection = build_client(status: true, response: 'node1.example.test')

    expect(client.get_session_node(101, 'session-token')).to eq('node1.example.test')

    payload = JSON.parse(connection.channel.exchange.published.fetch(0).fetch(:payload))

    expect(payload).to eq(
      'command' => 'get_session_node',
      'args' => [101, 'session-token'],
      'kwargs' => {}
    )
  ensure
    client&.close
  end

  it 'raises an RPC error when the response status is false' do
    client, = build_client(status: false, message: 'Server error')

    expect { client.get_api_url }.to raise_error(described_class::Error, 'Server error')
  ensure
    client&.close
  end

  it 'closes the reply queue and channel from .run' do
    connection = RpcFakeConnection.new(
      response_payload: { status: true, response: 'http://api.example.test' }
    )

    described_class.run(connection) do |rpc|
      expect(rpc.get_api_url).to eq('http://api.example.test')
    end

    expect(connection.channel.queues.fetch('reply-queue')).to be_deleted
    expect(connection.channel).to be_closed
  end
end
