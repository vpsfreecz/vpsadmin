# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/console'
require 'nodectld/console_events'
require 'nodectld/console/server'
require 'nodectld/console/wrapper'

class ConsoleServerSpecWrapper
  attr_reader :sessions, :stopped, :vps_id, :writes
  attr_writer :alive

  def initialize(vps_id, session)
    @vps_id = vps_id
    @sessions = [session]
    @writes = []
    @alive = true
    @stopped = false
  end

  def start; end

  def stop
    @stopped = true
  end

  def add_session(session)
    return false if sessions.include?(session)

    sessions << session
    true
  end

  def write(*args)
    writes << args
  end

  def alive?
    @alive
  end

  def in_use?
    sessions.any?
  end
end

RSpec.describe NodeCtld::Console do
  describe NodeCtld::Console::Server do
    let(:server) { described_class.new }
    let(:client_id) { '0123456789abcdef0123456789abcdef' }
    let(:token) { 'console-token-that-must-not-be-published' }
    let(:wrappers) { [] }
    let(:auth_context) do
      {
        'vps_id' => 101,
        'user_id' => 202,
        'vps_console_id' => 303
      }
    end

    before do
      allow(NodeCtld::ConsoleEvents).to receive(:publish)
      allow(server).to receive(:authenticate).with(token).and_return(auth_context)
      stub_const('NodeCtld::Console::Wrapper', Class.new)
      allow(NodeCtld::Console::Wrapper).to receive(:new) do |_server, vps_id, session|
        ConsoleServerSpecWrapper.new(vps_id, session).tap { |wrapper| wrappers << wrapper }
      end
    end

    def write_console(id = client_id)
      server.send(
        :open_write_console,
        'session' => token,
        'client_id' => id,
        'width' => 80,
        'height' => 25
      )
    end

    it 'reports an opened event once for an authenticated browser client' do
      write_console
      write_console

      expect(server).to have_received(:authenticate).once
      expect(NodeCtld::ConsoleEvents).to have_received(:publish).once.with(
        action: 'opened',
        vps_id: 101,
        client_id:,
        actor_user_id: 202,
        vps_console_id: 303,
        reason: nil
      )
      expect(wrappers.fetch(0).writes.size).to eq(2)
    end

    it 'tracks browser clients separately even when they reuse one token' do
      other_client_id = 'fedcba9876543210fedcba9876543210'

      write_console
      write_console(other_client_id)

      expect(wrappers.size).to eq(1)
      expect(wrappers.fetch(0).sessions.map(&:client_id)).to contain_exactly(
        client_id,
        other_client_id
      )
      expect(wrappers.fetch(0).sessions.map(&:output_key)).to contain_exactly(
        client_id,
        other_client_id
      )
      expect(NodeCtld::ConsoleEvents).to have_received(:publish).twice
    end

    it 'closes an explicitly disconnected browser client' do
      write_console

      server.send(
        :close_console_client,
        'session' => token,
        'client_id' => client_id,
        'reason' => 'client_closed'
      )

      expect(NodeCtld::ConsoleEvents).to have_received(:publish).with(
        action: 'closed',
        vps_id: 101,
        client_id:,
        actor_user_id: 202,
        vps_console_id: 303,
        reason: 'client_closed'
      )
      expect(wrappers.fetch(0).stopped).to be(true)
      expect(server.stats).to be_empty
    end

    it 'reports a close when an inactive client times out' do
      now = Time.utc(2026, 7, 28, 12, 0, 0)
      write_console
      wrappers.fetch(0).sessions.fetch(0).last_input = now - 61

      server.send(:prune_sessions, now, 60)
      server.send(:prune_sessions, now, 60)

      expect(NodeCtld::ConsoleEvents).to have_received(:publish).once.with(
        action: 'closed',
        vps_id: 101,
        client_id:,
        actor_user_id: 202,
        vps_console_id: 303,
        reason: 'session_timeout'
      )
    end

    it 'keeps legacy router messages working without exposing their token as a client id' do
      allow(SecureRandom).to receive(:hex).with(16).and_return(
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      )

      write_console(nil)
      write_console(nil)

      session = wrappers.fetch(0).sessions.fetch(0)
      expect(session.output_key).to eq(token[0..19])
      expect(session.client_id).to eq('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')
      expect(NodeCtld::ConsoleEvents).to have_received(:publish).once.with(
        action: 'opened',
        vps_id: 101,
        client_id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        actor_user_id: 202,
        vps_console_id: 303,
        reason: nil
      )
    end

    it 'keeps working with actor-less context from the legacy API fallback' do
      auth_context.replace('vps_id' => 101)

      write_console

      expect(NodeCtld::ConsoleEvents).to have_received(:publish).once.with(
        action: 'opened',
        vps_id: 101,
        client_id:,
        actor_user_id: nil,
        vps_console_id: nil,
        reason: nil
      )
    end

    it 'closes every live session exactly once during orderly shutdown' do
      other_client_id = 'fedcba9876543210fedcba9876543210'
      write_console
      write_console(other_client_id)

      server.stop(reason: 'node_shutdown')
      server.stop(reason: 'node_shutdown')

      expect(NodeCtld::ConsoleEvents).to have_received(:publish).once.with(
        action: 'closed',
        vps_id: 101,
        client_id:,
        actor_user_id: 202,
        vps_console_id: 303,
        reason: 'node_shutdown'
      )
      expect(NodeCtld::ConsoleEvents).to have_received(:publish).once.with(
        action: 'closed',
        vps_id: 101,
        client_id: other_client_id,
        actor_user_id: 202,
        vps_console_id: 303,
        reason: 'node_shutdown'
      )
      expect(wrappers.fetch(0).stopped).to be(true)
      expect(server.stats).to be_empty
    end
  end

  describe NodeCtld::ConsoleEvents do
    it 'publishes safe console context with a stable producer id using the waiting path' do
      exchange = stub_node_bunny
      now = Time.at(1_780_000_000, 123_456)
      producer_event_id = '12345678-1234-4abc-8def-123456789abc'
      payload = nil
      allow(Time).to receive(:now).and_return(now)
      allow(SecureRandom).to receive(:uuid).and_return(producer_event_id)
      allow(NodeCtld::NodeBunny).to receive(:publish_drop)
      allow(NodeCtld::NodeBunny).to receive(:publish_wait) do |_exchange, body, **opts|
        expect(opts).to include(
          routing_key: described_class::ROUTING_KEY,
          persistent: true
        )
        payload = JSON.parse(body)
      end

      described_class.publish(
        action: 'opened',
        vps_id: 101,
        client_id: '0123456789abcdef0123456789abcdef',
        actor_user_id: 202,
        vps_console_id: 303
      )

      expect(payload).to eq(
        'producer_event_id' => producer_event_id,
        'action' => 'opened',
        'vps_id' => 101,
        'client_id' => '0123456789abcdef0123456789abcdef',
        'actor_user_id' => 202,
        'vps_console_id' => 303,
        'reason' => nil,
        'time' => now.to_i,
        'time_f' => now.to_f
      )
      expect(JSON.dump(payload)).not_to include('token')
      expect(exchange).to be_present
      expect(NodeCtld::NodeBunny).not_to have_received(:publish_drop)
    end
  end

  describe NodeCtld::Console::Wrapper do
    it 'routes output to the browser client instead of the reusable console token' do
      session = NodeCtld::Console::Server::Session.new(
        vps_id: 101,
        token: 'console-token',
        client_id: '0123456789abcdef0123456789abcdef',
        output_key: '0123456789abcdef0123456789abcdef',
        key: 'session-key',
        actor_user_id: 202,
        vps_console_id: 303,
        last_input: Time.now
      )
      wrapper = described_class.new(nil, 101, session)

      expect(wrapper.send(:routing_key, session)).to eq(
        '101-0123456789abcdef0123456789abcdef'
      )
    end
  end
end
