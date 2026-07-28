# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/ct_monitor'

RSpec.describe NodeCtld::CtMonitor do
  let(:exchange) { Object.new }
  let(:monitor) do
    described_class.allocate.tap do |instance|
      instance.instance_variable_set(:@exchange, exchange)
    end
  end

  it 'assigns every published VPS event a stable producer event ID' do
    producer_event_id = '12345678-1234-4abc-8def-123456789abc'
    allow(SecureRandom).to receive(:uuid).and_return(producer_event_id)
    allow(NodeCtld::NodeBunny).to receive(:publish_wait)
    time = Time.utc(2026, 4, 5, 17, 0, 0)

    monitor.send(
      :send_event,
      101,
      'exit',
      { 'exit_type' => 'halt' },
      time:
    )

    expect(NodeCtld::NodeBunny).to have_received(:publish_wait) do |target, payload, **opts|
      expect(target).to equal(exchange)
      expect(JSON.parse(payload)).to eq(
        'id' => 101,
        'producer_event_id' => producer_event_id,
        'time' => time.to_i,
        'type' => 'exit',
        'opts' => { 'exit_type' => 'halt' }
      )
      expect(opts).to include(
        content_type: 'application/json',
        routing_key: 'vps_events'
      )
    end
  end
end
