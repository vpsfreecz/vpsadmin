# frozen_string_literal: true

require 'spec_helper'
require 'socket'
require 'nodectld/remote_client'

RSpec.describe NodeCtld::RemoteClient do
  def with_unix_server
    Dir.mktmpdir do |dir|
      sock_path = File.join(dir, 'nodectld.sock')
      server = UNIXServer.new(sock_path)

      begin
        yield(sock_path, server)
      ensure
        server.close
      end
    end
  end

  it 'opens, reads the greeting, sends a command, and parses the reply' do
    with_unix_server do |sock_path, server|
      server_thread = Thread.new do
        client = server.accept
        client.puts({ version: 'spec' }.to_json)
        req = JSON.parse(client.gets, symbolize_names: true)

        expect(req).to eq(command: 'ping', params: { a: 1 })

        client.puts({ status: :ok, response: { pong: :pong } }.to_json)
        client.close
      end

      remote = described_class.new(sock_path)
      remote.open
      remote.cmd(:ping, a: 1)

      expect(remote.reply).to eq(status: 'ok', response: { pong: 'pong' })
      expect(remote.instance_variable_get(:@version)).to eq('spec')

      remote.close
      server_thread.join
    end
  end

  it 'provides a send round-trip helper' do
    with_unix_server do |sock_path, server|
      server_thread = Thread.new do
        client = server.accept
        client.puts({ version: 'spec' }.to_json)
        req = JSON.parse(client.gets, symbolize_names: true)
        client.puts({ status: :ok, response: { command: req[:command] } }.to_json)
        client.close
      end

      expect(described_class.send(sock_path, :status)).to eq(
        status: 'ok',
        response: { command: 'status' }
      )

      server_thread.join
    end
  end

  it 'swallows connection failures in send_or_not' do
    expect(described_class.send_or_not('/tmp/missing-nodectld-spec.sock', :ping)).to be_nil
  end
end
