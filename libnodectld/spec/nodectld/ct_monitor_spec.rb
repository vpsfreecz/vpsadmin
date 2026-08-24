# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/ct_monitor'

RSpec.describe NodeCtld::CtMonitor do
  let(:ct_top) { instance_double(NodeCtld::CtTop, refresh: nil) }
  let(:daemon) { instance_double(NodeCtld::Daemon, ct_top:) }
  let(:monitor) do
    monitor_class = Class.new(described_class) do
      attr_reader :sent_events

      def send_event(vps_id, type, opts, time: nil)
        sent_events << [vps_id, type, opts, time]
      end
    end

    monitor_class.allocate.tap do |instance|
      instance.instance_variable_set(:@sent_events, [])
    end
  end

  before do
    allow(NodeCtld::Daemon).to receive(:instance).and_return(daemon)
    allow(NodeCtld::VpsPostStart).to receive(:run)
    allow(NodeCtld::MountReporter).to receive(:report)
    allow(NodeCtld::VethMap).to receive(:reset)
  end

  it 'derives vpsAdmin state events from runtime state events' do
    monitor.send(
      :process_event,
      type: 'runtime_state',
      opts: { id: '101', runtime_state: 'running' }
    )

    expect(monitor.sent_events).to eq(
      [[101, 'state', { 'state' => 'running' }, nil]]
    )
    expect(NodeCtld::VpsPostStart).to have_received(:run).with(101)
    expect(ct_top).to have_received(:refresh)
  end

  it 'accepts legacy state events during a rolling upgrade' do
    monitor.send(
      :process_event,
      type: 'state',
      opts: { id: '101', state: 'stopped' }
    )

    expect(monitor.sent_events).to eq(
      [[101, 'state', { 'state' => 'stopped' }, nil]]
    )
    expect(NodeCtld::MountReporter).to have_received(:report).with(
      '101',
      :all,
      :unmounted
    )
    expect(NodeCtld::VethMap).to have_received(:reset).with(101)
    expect(ct_top).to have_received(:refresh)
  end

  it 'does not map configuration state events to vpsAdmin runtime state' do
    monitor.send(
      :process_event,
      type: 'config_state',
      opts: { id: '101', config_state: 'error' }
    )

    expect(monitor.sent_events).to be_empty
    expect(ct_top).not_to have_received(:refresh)
  end
end
