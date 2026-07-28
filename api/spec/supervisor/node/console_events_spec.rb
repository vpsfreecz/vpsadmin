# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::Supervisor::Node::ConsoleEvents do
  let(:node) { SpecSeed.node }
  let(:supervisor) { described_class.new(nil, node) }
  let(:client_id) { '0123456789abcdef0123456789abcdef' }
  let(:timestamp) { Time.at(1_780_000_000, 123_456) }
  let(:vps) { build_standalone_vps_fixture(node:).fetch(:vps) }

  def actor
    SpecSeed.admin
  end

  def vps_console
    @vps_console ||= VpsConsole.create!(
      user: actor,
      vps:,
      token: SecureRandom.hex(50),
      expiration: Time.now + 60
    )
  end

  def producer_event_id
    '12345678-1234-4abc-8def-123456789abc'
  end

  def console_event(action, vps_id: vps.id, reason: nil)
    {
      'producer_event_id' => producer_event_id,
      'action' => action,
      'vps_id' => vps_id,
      'client_id' => client_id,
      'actor_user_id' => actor.id,
      'vps_console_id' => vps_console.id,
      'reason' => reason,
      'time' => timestamp.to_i,
      'time_f' => timestamp.to_f
    }
  end

  it 'defines owner-visible console events without default notification routing' do
    %w[vps.console_opened vps.console_closed].each do |event_name|
      type = VpsAdmin::API::Events.type_for(event_name)

      expect(type).to be_present
      expect(type.roles).to eq(%w[account admin])
      expect(type.default_routed).to be(false)
    end
  end

  describe '#start' do
    it 'acks each delivery after commit and deduplicates redelivery' do
      channel = SupervisorConsumerHelpers::FakeSupervisorChannel.new
      described_class.new(channel, node).start
      queue = channel.queues.fetch("node:#{node.domain_name}:console_events")
      processing_order = []
      allow(Vps).to receive(:find_by).and_call_original
      allow(Vps).to receive(:find_by)
        .with(id: vps.id, node_id: node.id)
        .and_return(vps)
      allow(vps).to receive(:with_lock).and_wrap_original do |original, *args, &block|
        original.call(*args, &block).tap { processing_order << :committed }
      end
      allow(channel).to receive(:ack).and_wrap_original do |original, tag|
        processing_order << :acked
        original.call(tag)
      end

      expect do
        queue.publish(console_event('opened').to_json)
        queue.publish(console_event('opened').to_json)
      end.to change(Event.where(event_type: 'vps.console_opened'), :count).by(1)

      expect(queue.subscribe_kwargs).to include(manual_ack: true)
      expect(channel.acked_tags).to eq([1, 1])
      expect(processing_order).to eq(%i[committed acked committed acked])
    end

    it 'does not acknowledge a delivery when persistence fails' do
      channel = SupervisorConsumerHelpers::FakeSupervisorChannel.new
      described_class.new(channel, node).start
      queue = channel.queues.fetch("node:#{node.domain_name}:console_events")
      allow(VpsAdmin::API::Events).to receive(:emit!)
        .and_raise(ActiveRecord::StatementInvalid, 'database unavailable')

      expect do
        queue.publish(console_event('opened').to_json)
      end.to raise_error(ActiveRecord::StatementInvalid, 'database unavailable')

      expect(channel.acked_tags).to be_empty
      expect(Event.where(event_type: 'vps.console_opened')).to be_empty
    end
  end

  it 'persists a console-open event from the node that hosts the VPS' do
    expect do
      supervisor.send(:process_event, console_event('opened'))
    end.to change(Event.where(event_type: 'vps.console_opened'), :count).by(1)

    event = Event.where(event_type: 'vps.console_opened').order(:id).last
    expect(event.user).to eq(vps.user)
    expect(event.vps).to eq(vps)
    expect(event.source).to eq(node)
    expect(event.created_at).to be_within(0.000_001).of(timestamp)
    expect(event.parameters).to include(
      'vps_id' => vps.id,
      'vps_hostname' => vps.hostname,
      'node_id' => node.id,
      'node_name' => node.domain_name,
      'console_client_id' => client_id,
      'producer_event_id' => producer_event_id,
      'actor_user_id' => actor.id,
      'vps_console_id' => vps_console.id
    )
    expect(event.user).not_to eq(actor)
    expect(event.parameters).not_to have_key('token')
  end

  it 'persists a correlated console-close event with its reason' do
    supervisor.send(
      :process_event,
      console_event('closed', reason: 'session_timeout')
    )

    event = Event.where(event_type: 'vps.console_closed').order(:id).last
    expect(event.parameters).to include(
      'console_client_id' => client_id,
      'close_reason' => 'session_timeout'
    )
  end

  it 'accepts actor-less messages from a mixed-version node' do
    message = console_event('opened')
    message.delete('producer_event_id')
    message.delete('actor_user_id')
    message.delete('vps_console_id')

    supervisor.send(:process_event, message)

    event = Event.where(event_type: 'vps.console_opened').order(:id).last
    expect(event.parameters).not_to have_key('actor_user_id')
    expect(event.parameters).not_to have_key('vps_console_id')
  end

  it 'ignores console messages for VPSes hosted by another node' do
    foreign_vps = build_standalone_vps_fixture(node: SpecSeed.other_node).fetch(:vps)

    expect do
      supervisor.send(
        :process_event,
        console_event('opened', vps_id: foreign_vps.id)
      )
    end.not_to change(Event.where(event_type: 'vps.console_opened'), :count)
  end

  it 'ignores unsupported actions and invalid client identifiers' do
    expect do
      supervisor.send(:process_event, console_event('connected'))
      supervisor.send(
        :process_event,
        console_event('opened').merge('client_id' => 'not-valid')
      )
      supervisor.send(
        :process_event,
        console_event('opened').merge('producer_event_id' => 'not-valid')
      )
    end.not_to change(Event.where(event_type: 'vps.console_opened'), :count)
  end

  it 'accepts orderly node shutdown as a truthful close reason' do
    supervisor.send(
      :process_event,
      console_event('closed', reason: 'node_shutdown')
    )

    event = Event.where(event_type: 'vps.console_closed').order(:id).last
    expect(event.parameters['close_reason']).to eq('node_shutdown')
  end
end
