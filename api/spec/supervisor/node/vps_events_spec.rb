# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::Supervisor::Node::VpsEvents do
  let(:node) { SpecSeed.node }
  let(:supervisor) { described_class.new(nil, node) }
  let(:timestamp) { Time.utc(2026, 4, 5, 17, 0, 0) }

  def event_payload(vps, type:, opts:, time: timestamp,
                    producer_event_id: '12345678-1234-4abc-8def-123456789abc')
    ret = {
      'id' => vps.id,
      'time' => time.to_i,
      'type' => type,
      'opts' => opts
    }
    ret['producer_event_id'] = producer_event_id if producer_event_id
    ret
  end

  def route_runtime_event!(vps, event_type)
    create_spec_event_route!(user: vps.user, event_type:)
  end

  describe '#start' do
    it 'manually acknowledges committed events and deduplicated redeliveries' do
      vps = build_standalone_vps_fixture(node:).fetch(:vps)
      set_vps_running!(vps)
      route_runtime_event!(vps, 'vps.runtime_halted')
      channel = SupervisorConsumerHelpers::FakeSupervisorChannel.new
      described_class.new(channel, node).start
      queue = channel.queues.fetch("node:#{node.domain_name}:vps_events")
      payload = event_payload(vps, type: 'exit', opts: { 'exit_type' => 'halt' })

      2.times { queue.publish(payload.to_json) }

      expect(queue.subscribe_kwargs).to eq(manual_ack: true)
      expect(channel.acked_tags).to eq([1, 1])
      expect(ObjectHistory.where(tracked_object: vps, event_type: 'halt').count).to eq(1)
      expect(Event.where(event_type: 'vps.runtime_halted', vps:).count).to eq(1)
    end

    it 'does not acknowledge events when their transaction rolls back' do
      vps = build_standalone_vps_fixture(node:).fetch(:vps)
      status = set_vps_running!(vps)
      channel = SupervisorConsumerHelpers::FakeSupervisorChannel.new
      described_class.new(channel, node).start
      queue = channel.queues.fetch("node:#{node.domain_name}:vps_events")
      allow(VpsAdmin::API::Events::VpsLifecycle).to receive(:emit_runtime!)
        .and_raise('event persistence failed')

      expect do
        queue.publish(
          event_payload(vps, type: 'exit', opts: { 'exit_type' => 'halt' }).to_json
        )
      end.to raise_error(RuntimeError, 'event persistence failed')

      expect(channel.acked_tags).to be_empty
      expect(status.reload.halted).to be(false)
      expect(ObjectHistory.where(tracked_object: vps, event_type: 'halt')).to be_empty
      expect(Event.where(event_type: 'vps.runtime_halted', vps:)).to be_empty
    end
  end

  describe '#process_event' do
    it 'logs halt events and marks current status as halted' do
      vps = build_standalone_vps_fixture(node:).fetch(:vps)
      status = set_vps_running!(vps)
      route_runtime_event!(vps, 'vps.runtime_halted')

      supervisor.send(:process_event, event_payload(vps, type: 'exit', opts: { 'exit_type' => 'halt' }))

      expect(status.reload.halted).to be(true)
      history = ObjectHistory.find_by!(tracked_object: vps, event_type: 'halt')
      expect(history.created_at).to eq(timestamp)
      event = Event.find_by!(event_type: 'vps.runtime_halted', vps:)
      expect(event).to have_attributes(
        user: vps.user,
        source: vps,
        created_at: timestamp
      )
      expect(event.payload).to include(
        'vps_id' => vps.id,
        'node_id' => node.id,
        'runtime_event_type' => 'halted',
        'producer_event_id' => '12345678-1234-4abc-8def-123456789abc'
      )
      expect(VpsAdmin::API::Events.default_routed?('vps.runtime_halted')).to be(false)
      expect(event.event_deliveries).to exist
    end

    it 'logs reboot events without marking current status as halted' do
      vps = build_standalone_vps_fixture(node:).fetch(:vps)
      status = set_vps_running!(vps)
      route_runtime_event!(vps, 'vps.runtime_rebooted')

      supervisor.send(:process_event, event_payload(vps, type: 'exit', opts: { 'exit_type' => 'reboot' }))

      expect(status.reload.halted).to be(false)
      history = ObjectHistory.find_by!(tracked_object: vps, event_type: 'reboot')
      expect(history.created_at).to eq(timestamp)
      event = Event.find_by!(event_type: 'vps.runtime_rebooted', vps:)
      expect(event).to have_attributes(
        user: vps.user,
        source: vps,
        created_at: timestamp
      )
      expect(event.payload).to include(
        'runtime_event_type' => 'rebooted'
      )
    end

    it 'creates an incident report for oomd stop events' do
      vps = build_standalone_vps_fixture(node:).fetch(:vps)
      route_runtime_event!(vps, 'vps.runtime_oom_stopped')
      allow(TransactionChains::IncidentReport::Utils).to receive(:fire_new)

      supervisor.send(:process_event, event_payload(vps, type: 'oomd', opts: { 'action' => 'stop' }))

      incident = IncidentReport.find_by!(vps:, codename: 'oomd')
      expect(incident.user).to eq(vps.user)
      expect(incident.subject).to eq('Stop due to abuse')
      expect(incident.text).to include('was stopped')
      expect(incident.detected_at).to eq(timestamp)
      expect(TransactionChains::IncidentReport::Utils).to have_received(:fire_new).with(incident)
      expect(ObjectHistory.find_by!(tracked_object: vps, event_type: 'stop').created_at).to eq(timestamp)
      event = Event.find_by!(event_type: 'vps.runtime_oom_stopped', vps:)
      expect(event).to have_attributes(
        user: vps.user,
        source: incident,
        created_at: timestamp,
        severity: 'warning'
      )
      expect(event.payload).to include(
        'incident_report_id' => incident.id,
        'runtime_event_type' => 'oom_stopped'
      )
    end

    it 'creates an incident report for oomd restart events' do
      vps = build_standalone_vps_fixture(node:).fetch(:vps)
      route_runtime_event!(vps, 'vps.runtime_oom_restarted')
      allow(TransactionChains::IncidentReport::Utils).to receive(:fire_new)

      supervisor.send(:process_event, event_payload(vps, type: 'oomd', opts: { 'action' => 'restart' }))

      incident = IncidentReport.find_by!(vps:, codename: 'oomd')
      expect(incident.subject).to eq('Restart due to abuse')
      expect(incident.text).to include('was restarted')
      expect(TransactionChains::IncidentReport::Utils).to have_received(:fire_new).with(incident)
      expect(ObjectHistory.find_by!(tracked_object: vps, event_type: 'restart').created_at).to eq(timestamp)
      event = Event.find_by!(event_type: 'vps.runtime_oom_restarted', vps:)
      expect(event).to have_attributes(
        user: vps.user,
        source: incident,
        created_at: timestamp,
        severity: 'warning'
      )
    end

    it 'does not duplicate OOM incidents or transaction work on redelivery' do
      vps = build_standalone_vps_fixture(node:).fetch(:vps)
      route_runtime_event!(vps, 'vps.runtime_oom_stopped')
      allow(TransactionChains::IncidentReport::Utils).to receive(:fire_new)
      payload = event_payload(vps, type: 'oomd', opts: { 'action' => 'stop' })

      2.times { supervisor.send(:process_event, payload) }

      expect(IncidentReport.where(vps:, codename: 'oomd').count).to eq(1)
      expect(ObjectHistory.where(tracked_object: vps, event_type: 'stop').count).to eq(1)
      expect(Event.where(event_type: 'vps.runtime_oom_stopped', vps:).count).to eq(1)
      expect(TransactionChains::IncidentReport::Utils).to have_received(:fire_new).once
    end

    it 'deduplicates unrouted runtime logging without an Event row' do
      vps = build_standalone_vps_fixture(node:).fetch(:vps)
      NotificationReceiver.ensure_defaults_for!(vps.user)
      EventRoute.update_all(enabled: false)
      payload = event_payload(
        vps,
        type: 'exit',
        opts: { 'exit_type' => 'halt' }
      )

      expect do
        2.times { supervisor.send(:process_event, payload) }
      end.not_to(change { event_storage_counts })

      history = ObjectHistory.where(
        tracked_object: vps,
        event_type: 'halt'
      ).sole
      expect(history.event_data).to include(
        'producer_event_id' => payload.fetch('producer_event_id')
      )
    end

    it 'deduplicates unrouted OOM incident work without an Event row' do
      vps = build_standalone_vps_fixture(node:).fetch(:vps)
      NotificationReceiver.ensure_defaults_for!(vps.user)
      EventRoute.update_all(enabled: false)
      allow(TransactionChains::IncidentReport::Utils).to receive(:fire_new)
      payload = event_payload(
        vps,
        type: 'oomd',
        opts: { 'action' => 'stop' }
      )

      expect do
        2.times { supervisor.send(:process_event, payload) }
      end.not_to(change { event_storage_counts })

      expect(IncidentReport.where(vps:, codename: 'oomd').count).to eq(1)
      expect(ObjectHistory.where(tracked_object: vps, event_type: 'stop').count)
        .to eq(1)
      expect(TransactionChains::IncidentReport::Utils).to have_received(:fire_new).once
    end

    it 'continues to process legacy messages without a producer event ID' do
      vps = build_standalone_vps_fixture(node:).fetch(:vps)
      route_runtime_event!(vps, 'vps.runtime_rebooted')
      payload = event_payload(
        vps,
        type: 'exit',
        opts: { 'exit_type' => 'reboot' },
        producer_event_id: nil
      )

      2.times { supervisor.send(:process_event, payload) }

      expect(ObjectHistory.where(tracked_object: vps, event_type: 'reboot').count).to eq(2)
      events = Event.where(event_type: 'vps.runtime_rebooted', vps:)
      expect(events.count).to eq(2)
      expect(events).to all(satisfy { |event| !event.payload.has_key?('producer_event_id') })
    end

    it 'ignores messages with an invalid producer event ID' do
      vps = build_standalone_vps_fixture(node:).fetch(:vps)

      expect do
        supervisor.send(
          :process_event,
          event_payload(
            vps,
            type: 'exit',
            opts: { 'exit_type' => 'halt' },
            producer_event_id: 'not-a-uuid'
          )
        )
      end.not_to change(Event.where(event_type: 'vps.runtime_halted', vps:), :count)

      expect(ObjectHistory.where(tracked_object: vps, event_type: 'halt')).to be_empty
    end

    it 'retains distinct runtime events delivered out of timestamp order' do
      vps = build_standalone_vps_fixture(node:).fetch(:vps)
      route_runtime_event!(vps, 'vps.runtime_rebooted')
      route_runtime_event!(vps, 'vps.runtime_halted')
      earlier = timestamp - 300

      supervisor.send(
        :process_event,
        event_payload(
          vps,
          type: 'exit',
          opts: { 'exit_type' => 'reboot' },
          producer_event_id: '12345678-1234-4abc-8def-123456789ab1'
        )
      )
      supervisor.send(
        :process_event,
        event_payload(
          vps,
          type: 'exit',
          opts: { 'exit_type' => 'halt' },
          time: earlier,
          producer_event_id: '12345678-1234-4abc-8def-123456789ab2'
        )
      )

      events = Event.where(vps:, event_type: described_class::RUNTIME_EVENT_TYPES).order(:id)
      expect(events.pluck(:event_type)).to eq(
        %w[vps.runtime_rebooted vps.runtime_halted]
      )
      expect(events.map(&:created_at)).to eq([timestamp, earlier])
    end

    it 'ignores events for VPSes on another node' do
      foreign_vps = build_standalone_vps_fixture(node: SpecSeed.other_node).fetch(:vps)
      status = set_vps_running!(foreign_vps)
      allow(TransactionChains::IncidentReport::Utils).to receive(:fire_new)

      supervisor.send(
        :process_event,
        event_payload(foreign_vps, type: 'exit', opts: { 'exit_type' => 'halt' })
      )
      supervisor.send(
        :process_event,
        event_payload(foreign_vps, type: 'oomd', opts: { 'action' => 'stop' })
      )

      expect(status.reload.halted).to be(false)
      expect(ObjectHistory.where(tracked_object: foreign_vps)).to be_empty
      expect(IncidentReport.where(vps: foreign_vps)).to be_empty
      expect(Event.where(vps: foreign_vps)).to be_empty
      expect(TransactionChains::IncidentReport::Utils).not_to have_received(:fire_new)
    end

    it 'raises on unsupported oomd actions' do
      vps = build_standalone_vps_fixture(node:).fetch(:vps)

      expect do
        supervisor.send(:process_event, event_payload(vps, type: 'oomd', opts: { 'action' => 'freeze' }))
      end.to raise_error(RuntimeError, /Unsupported oomd action "freeze"/)
    end
  end
end
