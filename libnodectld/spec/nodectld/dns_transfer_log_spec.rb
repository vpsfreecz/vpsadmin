# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/queues'
require 'nodectld/dns_config'
require 'nodectld/dns_transfer_log'

RSpec.describe NodeCtld::DnsTransferLog do
  def dns_config(zones)
    Struct.new(:zones) do
      def [](name)
        zones[name]
      end
    end.new(zones)
  end

  before do
    stub_node_bunny
  end

  it 'normalizes known transfer failure messages' do
    log = described_class.new

    cases = {
      "transfer of 'refused.test/IN' from 192.0.2.1#53: Transfer status: REFUSED" => 'refused',
      "transfer of 'notauth.test/IN' from 192.0.2.1#53: Transfer status: NOTAUTH" => 'not_authoritative',
      "transfer of 'missing.test/IN' from 192.0.2.1#53: Transfer status: NXDOMAIN" => 'not_found',
      "transfer of 'servfail.test/IN' from 192.0.2.1#53: Transfer status: SERVFAIL" => 'servfail',
      'zone timeout.test/IN: refresh: failure trying primary 192.0.2.1#53: timed out' => 'timeout',
      "transfer of 'conn.test/IN' from 192.0.2.1#53: failed while receiving responses: connection refused" => 'connection_failed',
      "transfer of 'tsig.test/IN' from 192.0.2.1#53: Transfer status: TSIG verify failure" => 'tsig_error',
      'zone invalid.test/IN: not loaded due to errors.' => 'invalid_zone',
      "transfer of 'unknown.test/IN' from 192.0.2.1#53: Transfer status: unexpected EOF" => 'unknown'
    }

    cases.each do |message, reason_code|
      event = log.send(:parse_message, message)

      expect(event).to include(
        status: 'failed',
        reason_code:
      )
      expect(event[:reason]).not_to be_nil
    end
  end

  it 'normalizes successful and started transfers' do
    log = described_class.new

    completed = log.send(
      :parse_message,
      "transfer of 'ok.test/IN' from 192.0.2.1#53: Transfer completed: " \
      '1 messages, 5 records, 400 bytes, 0.001 secs (serial 2026050901)'
    )
    started = log.send(:parse_message, 'zone ok.test/IN: Transfer started.')

    expect(completed).to include(
      name: 'ok.test.',
      status: 'success',
      primary_addr: '192.0.2.1',
      serial: 2_026_050_901
    )
    expect(started).to include(
      name: 'ok.test.',
      status: 'started'
    )
  end

  it 'publishes recognized events and advances the cursor afterwards' do
    Dir.mktmpdir do |dir|
      cursor_file = File.join(dir, 'dns-transfer.cursor')
      $CFG = runtime_cfg(
        vpsadmin: { node_id: 7 },
        dns_server: { transfer_log_cursor_file: cursor_file }
      )
      published = []
      log = described_class.new
      entry = {
        '__CURSOR' => 'cursor-1',
        '__REALTIME_TIMESTAMP' => '1778323200000000',
        'MESSAGE' => "transfer of 'refused.test/IN' from 192.0.2.1#53: Transfer status: REFUSED"
      }

      allow(NodeCtld::DnsConfig).to receive(:instance).and_return(
        dns_config('refused.test.' => true)
      )
      allow(NodeCtld::NodeBunny).to receive(:publish_wait) do |_exchange, payload, **_opts|
        published << JSON.parse(payload)
      end

      log.send(:process_journal_line, "#{JSON.dump(entry)}\n")

      expect(published.length).to eq(1)
      expect(published.first.fetch('events').first).to include(
        'name' => 'refused.test.',
        'status' => 'failed',
        'reason_code' => 'refused',
        'source_cursor' => 'cursor-1'
      )
      expect(File.read(cursor_file).strip).to eq('cursor-1')
    end
  end
end
