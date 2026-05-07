# frozen_string_literal: true

require 'spec_helper'

class RouterFakeRpc
  attr_reader :session_node_calls

  def initialize(api_url: 'http://api.example.test', session_nodes: {})
    @api_url = api_url
    @session_nodes = session_nodes
    @session_node_calls = []
  end

  def run(_connection)
    yield(self)
  end

  def get_api_url
    @api_url
  end

  def get_session_node(vps_id, session)
    @session_node_calls << [vps_id, session]
    @session_nodes[[vps_id, session]]
  end
end

class RouterFakeConnection
  attr_reader :channels

  def initialize
    @channels = []
  end

  def create_channel
    channel = RouterFakeChannel.new
    @channels << channel
    channel
  end
end

class RouterFakeChannel
  attr_reader :closed, :exchanges, :queues

  def initialize
    @exchanges = {}
    @queues = {}
    @closed = false
  end

  def direct(name)
    @exchanges[name] ||= RouterFakeExchange.new(name)
  end

  def queue(name, **opts)
    @queues[name] ||= RouterFakeQueue.new(name, opts)
  end

  def close
    @closed = true
  end

  def closed?
    @closed
  end
end

class RouterFakeExchange
  attr_reader :name, :published

  def initialize(name)
    @name = name
    @published = []
  end

  def publish(payload, **opts)
    @published << { payload: payload, opts: opts }
  end
end

class RouterFakeQueue
  attr_reader :bindings, :name, :opts
  attr_accessor :payloads, :raise_timeout

  def initialize(name, opts)
    @name = name
    @opts = opts
    @bindings = []
    @payloads = []
    @raise_timeout = false
  end

  def bind(exchange, routing_key:)
    @bindings << { exchange: exchange, routing_key: routing_key }
  end

  def pop
    raise Timeout::Error if raise_timeout

    payload = @payloads.shift
    [nil, nil, payload]
  end
end

RSpec.describe VpsAdmin::ConsoleRouter::Router do
  let(:connection) { RouterFakeConnection.new }
  let(:rpc) do
    RouterFakeRpc.new(
      session_nodes: {
        [101, 'session-token'] => 'node1.example.test',
        [101, 'another-token'] => 'node1.example.test'
      }
    )
  end

  def build_router
    described_class.new(connection: connection, rpc_client: rpc, start_upkeep: false)
  end

  def input_exchange
    connection.channels.fetch(0).exchanges.fetch('console:node1.example.test:input')
  end

  def output_queue(session = 'session-token')
    connection.channels.fetch(0).queues.fetch("console:output:101-#{session[0..19]}")
  end

  it 'fetches the API URL on initialization' do
    expect(build_router.api_url).to eq('http://api.example.test')
  end

  it 'creates broker resources for a valid session' do
    router = build_router

    expect(router.check_session(101, 'session-token')).to be(true)

    channel = connection.channels.fetch(0)
    queue = output_queue

    expect(channel.exchanges.keys).to contain_exactly(
      'console:node1.example.test:input',
      'console:node1.example.test:output'
    )
    expect(queue.opts).to eq(
      durable: true,
      arguments: { 'x-queue-type' => 'quorum' }
    )
    expect(queue.bindings.fetch(0)).to include(
      exchange: channel.exchanges.fetch('console:node1.example.test:output'),
      routing_key: '101-session-token'
    )
  end

  it 'does not create a broker channel for an invalid session' do
    router = build_router

    expect(router.check_session(101, 'missing-token')).to be(false)
    expect(connection.channels).to be_empty
  end

  it 'reuses cached sessions without another RPC lookup' do
    router = build_router

    expect(router.read_write_console(101, 'session-token', nil, 80, 25)).to eq('')
    expect(router.read_write_console(101, 'session-token', nil, 80, 25)).to eq('')

    expect(rpc.session_node_calls).to eq([[101, 'session-token']])
    expect(connection.channels.length).to eq(1)
    expect(input_exchange.published.length).to eq(2)
  end

  it 'revalidates stale cached sessions' do
    router = build_router

    expect(router.check_session(101, 'session-token')).to be(true)

    entry = router.instance_variable_get(:@cache).fetch('101-session-token')
    entry.last_check = Time.now - described_class::SESSION_TIMEOUT - 1

    expect(router.check_session(101, 'session-token')).to be(true)
    expect(rpc.session_node_calls).to eq(
      [
        [101, 'session-token'],
        [101, 'session-token']
      ]
    )
  end

  it 'publishes terminal size and strict-base64 encoded keys' do
    router = build_router

    router.read_write_console(101, 'session-token', "ls\n", 120, 40)

    message = JSON.parse(input_exchange.published.fetch(0).fetch(:payload))

    expect(message).to eq(
      'session' => 'session-token',
      'width' => 120,
      'height' => 40,
      'keys' => Base64.strict_encode64("ls\n")
    )
  end

  it 'omits keys when no input was provided' do
    router = build_router

    router.read_write_console(101, 'session-token', '', 80, 25)

    message = JSON.parse(input_exchange.published.fetch(0).fetch(:payload))

    expect(message).to eq(
      'session' => 'session-token',
      'width' => 80,
      'height' => 25
    )
  end

  it 'concatenates pending console output' do
    router = build_router

    router.check_session(101, 'session-token')
    output_queue.payloads = ['hello ', "world\n"]

    expect(router.read_write_console(101, 'session-token', nil, 80, 25)).to eq("hello world\n")
  end

  it 'ignores queue timeout while reading output' do
    router = build_router

    router.check_session(101, 'session-token')
    output_queue.raise_timeout = true

    expect(router.read_write_console(101, 'session-token', nil, 80, 25)).to eq('')
  end

  it 'closes and removes idle cache entries' do
    router = build_router

    router.check_session(101, 'session-token')

    entry = router.instance_variable_get(:@cache).fetch('101-session-token')
    entry.last_use = Time.now - 61

    router.send(:prune_cache, Time.now)

    expect(connection.channels.fetch(0)).to be_closed
    expect(router.instance_variable_get(:@cache)).to be_empty
  end
end
