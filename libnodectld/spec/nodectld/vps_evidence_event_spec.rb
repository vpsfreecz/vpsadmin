require 'spec_helper'
require 'nodectld/ct_monitor'
require 'nodectld/node_bunny'

RSpec.describe NodeCtld::CtMonitor do
  subject(:monitor) { described_class.allocate }

  let(:fixture) { JSON.parse(File.read(File.expand_path('../fixtures/vps_evidence_v1.json', __dir__)), symbolize_names: true) }

  let(:publisher) { class_double(NodeCtld::NodeBunny) }
  let(:messages) { [] }

  before do
    stub_const('NodeCtld::NodeBunny', publisher)
    allow(publisher).to receive(:publish_wait) do |exchange, raw, **options|
      messages << { exchange:, event: JSON.parse(raw, symbolize_names: true), options: }
    end
    monitor.instance_variable_set(:@exchange, :exchange)
  end

  it 'forwards the complete canonical batch including identities unchanged as a node-scoped event' do
    monitor.send(:process_event, fixture)
    expect(messages.sole).to eq(exchange: :exchange,
                                event: { id: nil, type: 'vps_evidence', time: fixture[:opts][:observed_at_us] / 1_000_000, opts: fixture[:opts] },
                                options: { content_type: 'application/json', routing_key: 'vps_events' })
  end

  it 'forwards a bounded empty heartbeat without inventing a VPS or refreshing source time' do
    fixture[:opts].merge!(kind: 'heartbeat', targets: [], segments: [])
    monitor.send(:process_event, fixture)
    expect(messages.sole).to eq(exchange: :exchange,
                                event: { id: nil, type: 'vps_evidence', time: fixture[:opts][:observed_at_us] / 1_000_000, opts: fixture[:opts] },
                                options: { content_type: 'application/json', routing_key: 'vps_events' })
  end

  it 'drops malformed or oversized batches before forwarding' do
    fixture[:opts][:targets] *= 17
    monitor.send(:process_event, fixture)
    fixture[:opts] = { schema: 1, observed_at_us: 1, targets: [], segments: [], excess: 'x' * 16_384 }
    monitor.send(:process_event, fixture)
    expect(publisher).not_to have_received(:publish_wait)
  end
end
