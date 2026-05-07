# frozen_string_literal: true

require 'spec_helper'
require 'timeout'
require 'nodectld/mount_reporter'

RSpec.describe NodeCtld::MountReporter do
  before do
    stub_node_bunny
  end

  it 'de-duplicates reports by mount id and keeps the newest state' do
    reporter = described_class.new

    reporter.report(101, 9, :mounted)
    reporter.report(101, 9, :delayed)

    expect(reporter.instance_variable_get(:@mounts)).to eq([
                                                             {
                                                               vps_id: 101,
                                                               id: 9,
                                                               state: :delayed
                                                             }
                                                           ])
  end

  it 'publishes queued mount states from the reporter thread' do
    reporter = described_class.new
    published = []

    allow(NodeCtld::NodeBunny).to receive(:publish_wait) do |_exchange, payload, **_opts|
      published << JSON.parse(payload)
    end

    reporter.report(101, 9, :mounted)
    reporter.start

    Timeout.timeout(3) do
      sleep 0.01 until published.any?
    end

    reporter.stop

    expect(published.first).to include(
      'id' => 9,
      'vps_id' => 101,
      'state' => 'mounted'
    )
  end

  it 'stops the reporter thread cleanly' do
    reporter = described_class.new

    reporter.start
    reporter.stop

    expect(reporter.instance_variable_get(:@thread)).not_to be_alive
  end
end
