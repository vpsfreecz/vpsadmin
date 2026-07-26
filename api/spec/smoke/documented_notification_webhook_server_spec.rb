# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'net/http'
require 'open3'
require 'openssl'
require 'socket'
require 'timeout'

RSpec.describe VpsAdmin::API::Notifications do
  let(:secret) { 'documentation-test-secret' }
  let(:example_dir) { File.expand_path('../../../doc/examples/notifications', __dir__) }
  let(:server) { File.join(example_dir, 'webhook_server.py') }
  let(:port) do
    probe = TCPServer.new('127.0.0.1', 0)
    ret = probe.addr.fetch(1)
    probe.close
    ret
  end
  let(:server_process) do
    Open3.popen3(
      {
        'WEBHOOK_SECRET' => secret,
        'WEBHOOK_HOST' => '127.0.0.1',
        'WEBHOOK_PORT' => port.to_s,
        'WEBHOOK_PATH' => '/events',
        'WEBHOOK_MAX_BODY_BYTES' => '65536'
      },
      'python3',
      server
    )
  end

  before do
    server_process.fetch(0).close

    Timeout.timeout(10) do
      loop do
        socket = TCPSocket.new('127.0.0.1', port)
        socket.close
        break
      rescue Errno::ECONNREFUSED
        sleep(0.05)
      end
    end
  end

  after do
    _stdin, stdout, stderr, thread = server_process
    Process.kill('TERM', thread.pid) if thread.alive?
    thread.join(5)
    stdout.close
    stderr.close
  end

  def example_payload(name)
    File.read(File.join(example_dir, name))
  end

  def post_webhook(body, secret: self.secret, delivery_id: nil)
    payload = JSON.parse(body)
    delivery_id ||= payload.dig('delivery', 'id').to_s
    signature = OpenSSL::HMAC.hexdigest('sha256', secret, body)
    request = Net::HTTP::Post.new('/events')
    request['Content-Type'] = 'application/json'
    request['X-VpsAdmin-Delivery'] = delivery_id
    request['X-VpsAdmin-Signature-256'] = "sha256=#{signature}"
    request.body = body

    Net::HTTP.start('127.0.0.1', port, nil) { |http| http.request(request) }
  end

  def raw_post(content_length)
    socket = TCPSocket.new('127.0.0.1', port)
    socket.write(
      "POST /events HTTP/1.1\r\n" \
      "Host: 127.0.0.1\r\n" \
      "Content-Length: #{content_length}\r\n" \
      "Connection: close\r\n\r\n"
    )
    socket.gets.split.fetch(1)
  ensure
    socket&.close
  end

  it 'accepts the documented single-event and grouped payloads' do
    single_response = post_webhook(example_payload('webhook_single.json'))
    grouped_response = post_webhook(example_payload('webhook_grouped.json'))

    expect(single_response.code).to eq('204')
    expect(grouped_response.code).to eq('204')
  end

  it 'keeps both fixtures aligned with the webhook version 1 payload shape' do
    single = JSON.parse(example_payload('webhook_single.json'))
    grouped = JSON.parse(example_payload('webhook_grouped.json'))

    [single, grouped].each do |payload|
      expect(payload.keys).to contain_exactly('version', 'group', 'events', 'delivery')
      expect(payload.fetch('version')).to eq(1)
      expect(payload.fetch('group').keys).to contain_exactly(
        'grouped', 'key', 'labels', 'event_count', 'truncated_count'
      )
      expect(payload.fetch('delivery').keys).to contain_exactly(
        'id', 'action', 'route', 'receiver', 'notification_target', 'receiver_target'
      )
      expect(payload.dig('delivery', 'route').keys).to contain_exactly(
        'id', 'label', 'matcher_summary'
      )
      expect(payload.dig('delivery', 'receiver').keys).to contain_exactly('id', 'label')
      expect(payload.fetch('events')).to all(
        include(
          'id', 'type', 'category', 'severity', 'subject', 'summary', 'payload',
          'fields', 'ip_addr', 'source', 'user', 'vps', 'created_at'
        )
      )
      expect(payload.dig('group', 'event_count')).to eq(payload.fetch('events').length)
      expect(payload.dig('group', 'truncated_count')).to eq(0)
      expect(payload.dig('delivery', 'action')).to eq('webhook')
    end

    expect(single.dig('group', 'grouped')).to be(false)
    expect(grouped.dig('group', 'grouped')).to be(true)
  end

  it 'rejects an invalid signature' do
    response = post_webhook(example_payload('webhook_single.json'), secret: 'wrong-secret')

    expect(response.code).to eq('401')
  end

  it 'rejects a mismatched delivery ID' do
    response = post_webhook(example_payload('webhook_single.json'), delivery_id: '9999')

    expect(response.code).to eq('400')
  end

  it 'rejects negative and oversized request bodies before reading them' do
    expect(raw_post(-1)).to eq('400')
    expect(raw_post(65_537)).to eq('413')
  end
end
