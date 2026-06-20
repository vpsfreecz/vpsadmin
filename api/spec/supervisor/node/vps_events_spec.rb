# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::Supervisor::Node::VpsEvents do
  let(:node) { SpecSeed.node }
  let(:supervisor) { described_class.new(nil, node) }
  let(:timestamp) { Time.utc(2026, 4, 5, 17, 0, 0) }

  def event_payload(vps, type:, opts:)
    {
      'id' => vps.id,
      'time' => timestamp.to_i,
      'type' => type,
      'opts' => opts
    }
  end

  describe '#process_event' do
    it 'logs halt events and marks current status as halted' do
      vps = build_standalone_vps_fixture(node:).fetch(:vps)
      status = set_vps_running!(vps)

      supervisor.send(:process_event, event_payload(vps, type: 'exit', opts: { 'exit_type' => 'halt' }))

      expect(status.reload.halted).to be(true)
      history = ObjectHistory.find_by!(tracked_object: vps, event_type: 'halt')
      expect(history.created_at).to eq(timestamp)
    end

    it 'logs reboot events without marking current status as halted' do
      vps = build_standalone_vps_fixture(node:).fetch(:vps)
      status = set_vps_running!(vps)

      supervisor.send(:process_event, event_payload(vps, type: 'exit', opts: { 'exit_type' => 'reboot' }))

      expect(status.reload.halted).to be(false)
      history = ObjectHistory.find_by!(tracked_object: vps, event_type: 'reboot')
      expect(history.created_at).to eq(timestamp)
    end

    it 'creates an incident report for oomd stop events' do
      vps = build_standalone_vps_fixture(node:).fetch(:vps)
      allow(TransactionChains::IncidentReport::Utils).to receive(:fire_new)

      supervisor.send(:process_event, event_payload(vps, type: 'oomd', opts: { 'action' => 'stop' }))

      incident = IncidentReport.find_by!(vps:, codename: 'oomd')
      expect(incident.user).to eq(vps.user)
      expect(incident.subject).to eq('Stop due to abuse')
      expect(incident.text).to include('was stopped')
      expect(incident.detected_at).to eq(timestamp)
      expect(TransactionChains::IncidentReport::Utils).to have_received(:fire_new).with(incident)
      expect(ObjectHistory.find_by!(tracked_object: vps, event_type: 'stop').created_at).to eq(timestamp)
    end

    it 'creates an incident report for oomd restart events' do
      vps = build_standalone_vps_fixture(node:).fetch(:vps)
      allow(TransactionChains::IncidentReport::Utils).to receive(:fire_new)

      supervisor.send(:process_event, event_payload(vps, type: 'oomd', opts: { 'action' => 'restart' }))

      incident = IncidentReport.find_by!(vps:, codename: 'oomd')
      expect(incident.subject).to eq('Restart due to abuse')
      expect(incident.text).to include('was restarted')
      expect(TransactionChains::IncidentReport::Utils).to have_received(:fire_new).with(incident)
      expect(ObjectHistory.find_by!(tracked_object: vps, event_type: 'restart').created_at).to eq(timestamp)
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
