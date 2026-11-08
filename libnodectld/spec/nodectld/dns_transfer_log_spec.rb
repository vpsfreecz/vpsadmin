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

  def parse(log, *messages)
    messages.filter_map { |message| log.send(:parse_message, message) }
  end

  before do
    stub_node_bunny
  end

  it 'correlates BIND 9.20 transfer failures by transfer pointer' do
    log = described_class.new
    events = parse(
      log,
      "0xabc: transfer of 'failed.test/IN' from 192.0.2.1#53: connected using 192.0.2.1#53",
      "0xabc: transfer of 'failed.test/IN' from 192.0.2.1#53: " \
      'failed while receiving responses: connection refused',
      "0xabc: transfer of 'failed.test/IN' from 192.0.2.1#53: Transfer status: connection refused",
      "0xabc: transfer of 'failed.test/IN' from 192.0.2.1#53: Transfer completed: " \
      '1 messages, 4 records, 300 bytes, 0.001 secs (300 bytes/sec) (serial 2026081301)'
    )

    expect(events).to contain_exactly(
      include(
        name: 'failed.test.',
        status: 'failed',
        attempt_kind: 'transfer',
        failure_class: 'network',
        reason_code: 'connection_failed',
        primary_addr: '192.0.2.1',
        message: 'failed while receiving responses: connection refused'
      )
    )
  end

  it 'resets correlation when BIND reuses a pointer for another path' do
    log = described_class.new
    zone_class = Struct.new(
      :id,
      :primary_transfer_generation,
      :primary_transfer_tracking_started_at,
      :user_primaries
    )
    config = dns_config(
      'old.test.' => zone_class.new(
        12,
        'old-generation',
        100,
        [{ 'id' => 20, 'kind' => 'user_primary', 'ip_addr' => '192.0.2.1' }]
      ),
      'new.test.' => zone_class.new(
        13,
        'new-generation',
        100,
        [{ 'id' => 21, 'kind' => 'user_primary', 'ip_addr' => '192.0.2.2' }]
      )
    )

    log.send(
      :parse_message,
      "0xabc: transfer of 'old.test/IN' from 192.0.2.1#53: connected",
      event_time: 101,
      dns_config: config
    )
    log.send(
      :parse_message,
      "0xabc: transfer of 'new.test/IN' from 192.0.2.2#53: connected",
      event_time: 102,
      dns_config: config
    )
    log.send(
      :parse_message,
      "0xabc: transfer of 'new.test/IN' from 192.0.2.2#53: " \
      'failed while receiving responses: REFUSED',
      event_time: 103,
      dns_config: config
    )
    event = log.send(
      :parse_message,
      "0xabc: transfer of 'new.test/IN' from 192.0.2.2#53: Transfer status: REFUSED",
      event_time: 104,
      dns_config: config
    )

    expect(event).to include(
      name: 'new.test.',
      primary_addr: '192.0.2.2',
      dns_server_zone_id: 13,
      dns_zone_transfer_id: 21,
      configuration_generation: 'new-generation',
      status: 'failed',
      failure_class: 'primary',
      reason_code: 'refused'
    )
  end

  it 'starts fresh correlation when a pointer is reused for the same path' do
    log = described_class.new
    zone_class = Struct.new(
      :id,
      :primary_transfer_generation,
      :primary_transfer_tracking_started_at,
      :user_primaries
    )
    old_zone = zone_class.new(
      12,
      'old-generation',
      100,
      [{ 'id' => 20, 'kind' => 'user_primary', 'ip_addr' => '192.0.2.1' }]
    )
    new_zone = zone_class.new(
      12,
      'new-generation',
      110,
      [{ 'id' => 21, 'kind' => 'user_primary', 'ip_addr' => '192.0.2.1' }]
    )

    log.send(
      :parse_message,
      "0xabc: transfer of 'same.test/IN' from 192.0.2.1#53: connected",
      event_time: 101,
      dns_config: dns_config('same.test.' => old_zone)
    )
    log.send(
      :parse_message,
      "0xabc: transfer of 'same.test/IN' from 192.0.2.1#53: connected",
      event_time: 111,
      dns_config: dns_config('same.test.' => new_zone)
    )
    event = log.send(
      :parse_message,
      "0xabc: transfer of 'same.test/IN' from 192.0.2.1#53: Transfer status: REFUSED",
      event_time: 112,
      dns_config: dns_config('same.test.' => new_zone)
    )

    expect(event).to include(
      dns_server_zone_id: 12,
      dns_zone_transfer_id: 21,
      configuration_generation: 'new-generation'
    )
  end

  it 'correlates BIND 9.18 transfer failures by zone and primary' do
    log = described_class.new
    events = parse(
      log,
      "transfer of 'refused.test/IN' from 2001:db8::1#53: connected using 2001:db8::1#53",
      "transfer of 'refused.test/IN' from 2001:db8::1#53: Transfer status: REFUSED"
    )

    expect(events).to contain_exactly(
      include(
        name: 'refused.test.',
        status: 'failed',
        attempt_kind: 'transfer',
        failure_class: 'primary',
        reason_code: 'refused',
        primary_addr: '2001:db8::1'
      )
    )
  end

  it 'uses accepted transferred serial messages as transfer success' do
    log = described_class.new
    events = parse(
      log,
      "0xabc: transfer of 'ok.test/IN' from 192.0.2.1#53: connected using 192.0.2.1#53",
      "zone ok.test/IN: transferred serial 2026081302: TSIG 'example-key'",
      "0xabc: transfer of 'ok.test/IN' from 192.0.2.1#53: Transfer status: success",
      "0xabc: transfer of 'ok.test/IN' from 192.0.2.1#53: Transfer completed: " \
      '1 messages, 5 records, 400 bytes, 0.001 secs (400 bytes/sec) (serial 2026081302)'
    )

    expect(events).to contain_exactly(
      include(
        name: 'ok.test.',
        status: 'success',
        attempt_kind: 'transfer',
        failure_class: nil,
        primary_addr: '192.0.2.1',
        serial: 2_026_081_302
      )
    )
  end

  it 'keeps terminal success through completion until transferred serial arrives' do
    log = described_class.new
    events = parse(
      log,
      "0xabc: transfer of 'ordered.test/IN' from 192.0.2.1#53: connected using 192.0.2.1#53",
      "0xabc: transfer of 'ordered.test/IN' from 192.0.2.1#53: Transfer status: success",
      "0xabc: transfer of 'ordered.test/IN' from 192.0.2.1#53: Transfer completed: " \
      '1 messages, 5 records, 400 bytes, 0.001 secs (400 bytes/sec) (serial 2026081306)',
      'zone ordered.test/IN: transferred serial 2026081306'
    )

    expect(events).to contain_exactly(
      include(
        name: 'ordered.test.',
        status: 'success',
        attempt_kind: 'transfer',
        failure_class: nil,
        primary_addr: '192.0.2.1',
        serial: 2_026_081_306
      )
    )
  end

  it 'ignores an uncorrelated transferred serial conservatively' do
    log = described_class.new

    expect(
      log.send(:parse_message, 'zone orphan.test/IN: transferred serial 2026081307')
    ).to be_nil
  end

  it 'never treats transfer completion accounting as success' do
    log = described_class.new

    [
      "transfer of 'empty.test/IN' from 192.0.2.1#53: Transfer completed: " \
      '0 messages, 0 records, 0 bytes, 132.454 secs (0 bytes/sec) (serial 0)',
      "transfer of 'partial.test/IN' from 192.0.2.1#53: Transfer completed: " \
      '2 messages, 25 records, 2048 bytes, 0.005 secs (409600 bytes/sec) (serial 2026081303)'
    ].each do |message|
      expect(log.send(:parse_message, message)).to be_nil
    end
  end

  it 'accepts an up-to-date transfer status without transferred serial' do
    log = described_class.new
    events = parse(
      log,
      "0xabc: transfer of 'current.test/IN' from 192.0.2.1#53: connected using 192.0.2.1#53",
      "0xabc: transfer of 'current.test/IN' from 192.0.2.1#53: Transfer status: UP TO DATE",
      "0xabc: transfer of 'current.test/IN' from 192.0.2.1#53: Transfer completed: " \
      '0 messages, 1 records, 0 bytes, 0.005 secs (0 bytes/sec) (serial 2026080601)'
    )

    expect(events).to contain_exactly(
      include(
        name: 'current.test.',
        status: 'success',
        attempt_kind: 'refresh',
        failure_class: nil,
        primary_addr: '192.0.2.1',
        message: 'Zone is up to date'
      )
    )
  end

  it 'uses an existing older-serial refresh response as network recovery' do
    log = described_class.new
    event = log.send(
      :parse_message,
      'zone current.test/IN: serial number (2026081308) received from ' \
      'primary 192.0.2.1#53 < ours (2026081309)'
    )

    expect(event).to include(
      name: 'current.test.',
      status: 'success',
      attempt_kind: 'refresh',
      failure_class: nil,
      primary_addr: '192.0.2.1',
      serial: 2_026_081_308,
      message: 'Primary responded with older serial 2026081308'
    )
  end

  it 'records transferred SOA and NS rejection instead of engine success' do
    log = described_class.new
    events = parse(
      log,
      "0xabc: transfer of 'invalid.test/IN' from 192.0.2.1#53: connected using 192.0.2.1#53",
      'zone invalid.test/IN: transferred zone has no NS records',
      "0xabc: transfer of 'invalid.test/IN' from 192.0.2.1#53: Transfer status: success",
      "0xabc: transfer of 'invalid.test/IN' from 192.0.2.1#53: Transfer completed: " \
      '1 messages, 1 records, 100 bytes, 0.001 secs (100 bytes/sec) (serial 2026081304)'
    )

    expect(events).to contain_exactly(
      include(
        name: 'invalid.test.',
        status: 'failed',
        attempt_kind: 'transfer',
        failure_class: 'primary',
        reason_code: 'invalid_zone',
        primary_addr: '192.0.2.1',
        message: 'transferred zone has no NS records'
      )
    )
  end

  it 'suppresses IXFR failure when BIND falls back to AXFR' do
    log = described_class.new
    events = parse(
      log,
      "transfer of 'fallback.test/IN' from 192.0.2.1#53: failed while processing responses: FORMERR",
      "transfer of 'fallback.test/IN' from 192.0.2.1#53: Transfer status: IXFR failed",
      "transfer of 'fallback.test/IN' from 192.0.2.1#53: Transfer completed: " \
      '1 messages, 2 records, 200 bytes, 0.001 secs (200 bytes/sec) (serial 2026081304)',
      "transfer of 'fallback.test/IN' from 192.0.2.1#53: connected using 192.0.2.1#53",
      'zone fallback.test/IN: transferred serial 2026081305'
    )

    expect(events).to contain_exactly(
      include(
        name: 'fallback.test.',
        status: 'success',
        attempt_kind: 'transfer',
        serial: 2_026_081_305
      )
    )
  end

  it 'classifies lifecycle and unrecognized transfer failures for admin-only use' do
    log = described_class.new

    lifecycle = log.send(
      :parse_message,
      "transfer of 'restart.test/IN' from 192.0.2.1#53: Transfer status: shutting down"
    )
    unknown = log.send(
      :parse_message,
      "transfer of 'unknown.test/IN' from 192.0.2.1#53: Transfer status: unexpected EOF"
    )

    expect(lifecycle).to include(
      status: 'failed',
      attempt_kind: 'transfer',
      failure_class: 'lifecycle',
      reason_code: 'unknown'
    )
    expect(unknown).to include(
      status: 'failed',
      attempt_kind: 'transfer',
      failure_class: 'unknown',
      reason_code: 'unknown'
    )
  end

  it 'normalizes terminal statuses exercised by upstream BIND transfer tests' do
    log = described_class.new
    cases = {
      'expected a TSIG or SIG(0)' => %w[tsig_error primary],
      'tsig verify failure' => %w[tsig_error primary],
      'clocks are unsynchronized' => %w[tsig_error primary],
      'clock skew' => %w[tsig_error primary],
      'tsig indicates error' => %w[tsig_error primary],
      'did not expect a TSIG or SIG(0)' => %w[tsig_error primary],
      'TSIG in wrong location' => %w[tsig_error primary],
      'FORMERR' => %w[protocol_error primary],
      'NOTIMP' => %w[protocol_error primary],
      'bad class' => %w[protocol_error primary],
      'extra input data' => %w[protocol_error primary],
      'label too long' => %w[protocol_error primary],
      'bad compression pointer' => %w[protocol_error primary],
      'unknown class/type' => %w[protocol_error primary],
      'syntax error' => %w[protocol_error primary],
      'bad checksum' => %w[protocol_error primary],
      'bad owner name (check-names)' => %w[protocol_error primary],
      'unexpected message id' => %w[protocol_error primary],
      'response with mismatched query id' => %w[protocol_error primary],
      'invalid NS owner name (wildcard)' => %w[invalid_zone primary],
      'BADVERS' => %w[protocol_error primary],
      'BADCOOKIE' => %w[protocol_error primary],
      'NOTZONE' => %w[protocol_error primary],
      'YXDOMAIN' => %w[protocol_error primary],
      'YXRRSET' => %w[protocol_error primary],
      'NXRRSET' => %w[protocol_error primary],
      '<rcode 11>' => %w[protocol_error primary],
      'NXDOMAIN' => %w[not_found primary],
      'SIG(0) in wrong location' => %w[tsig_error primary],
      'too many records' => %w[invalid_zone primary]
    }

    cases.each_with_index do |(status, expected), i|
      event = log.send(
        :parse_message,
        "transfer of 'status-#{i}.test/IN' from 192.0.2.1#53: Transfer status: #{status}"
      )

      expect(event).to include(
        status: 'failed',
        attempt_kind: 'transfer',
        reason_code: expected[0],
        failure_class: expected[1]
      )
    end
  end

  it 'does not blame the primary for a generic local not-found result' do
    log = described_class.new

    ['not found', 'does not exist'].each_with_index do |status, i|
      event = log.send(
        :parse_message,
        "transfer of 'local-not-found-#{i}.test/IN' from 192.0.2.1#53: " \
        "Transfer status: #{status}"
      )

      expect(event).to include(
        status: 'failed',
        reason_code: 'unknown',
        failure_class: 'unknown'
      )
    end
  end

  it 'classifies a complete NXDOMAIN response sequence as a primary failure' do
    log = described_class.new
    events = parse(
      log,
      "0xabc: transfer of 'missing.test/IN' from 192.0.2.1#53: connected using 192.0.2.1#53",
      "0xabc: transfer of 'missing.test/IN' from 192.0.2.1#53: " \
      'failed while receiving responses: NXDOMAIN',
      "0xabc: transfer of 'missing.test/IN' from 192.0.2.1#53: Transfer status: NXDOMAIN"
    )

    expect(events).to contain_exactly(
      include(
        status: 'failed',
        reason_code: 'not_found',
        failure_class: 'primary',
        message: 'failed while receiving responses: NXDOMAIN'
      )
    )
  end

  it 'uses receive-response context for BIND unexpected-error status' do
    log = described_class.new
    events = parse(
      log,
      "0xabc: transfer of 'bad-id.test/IN' from 192.0.2.1#53: connected using 192.0.2.1#53",
      "0xabc: transfer of 'bad-id.test/IN' from 192.0.2.1#53: " \
      'failed while receiving responses: unexpected error',
      "0xabc: transfer of 'bad-id.test/IN' from 192.0.2.1#53: Transfer status: unexpected error"
    )

    expect(events).to contain_exactly(
      include(
        status: 'failed',
        attempt_kind: 'transfer',
        reason_code: 'protocol_error',
        failure_class: 'primary',
        message: 'failed while receiving responses: unexpected error'
      )
    )

    expect(
      log.send(
        :parse_message,
        "transfer of 'orphan.test/IN' from 192.0.2.1#53: Transfer status: unexpected error"
      )
    ).to include(reason_code: 'unknown', failure_class: 'unknown')
  end

  it 'classifies a primary closing a partial transfer as a network failure' do
    log = described_class.new
    events = parse(
      log,
      "0xabc: transfer of 'partial.test/IN' from 192.0.2.1#53: connected using 192.0.2.1#53",
      "0xabc: transfer of 'partial.test/IN' from 192.0.2.1#53: " \
      'failed while receiving responses: end of file',
      "0xabc: transfer of 'partial.test/IN' from 192.0.2.1#53: Transfer status: end of file"
    )

    expect(events).to contain_exactly(
      include(
        status: 'failed',
        attempt_kind: 'transfer',
        reason_code: 'connection_failed',
        failure_class: 'network',
        message: 'failed while receiving responses: end of file'
      )
    )
  end

  it 'classifies malformed RDATA ending unexpectedly as a primary protocol failure' do
    log = described_class.new
    events = parse(
      log,
      "0xabc: transfer of 'malformed.test/IN' from 192.0.2.1#53: connected using 192.0.2.1#53",
      "0xabc: transfer of 'malformed.test/IN' from 192.0.2.1#53: " \
      'failed while receiving responses: unexpected end of input',
      "0xabc: transfer of 'malformed.test/IN' from 192.0.2.1#53: " \
      'Transfer status: unexpected end of input'
    )

    expect(events).to contain_exactly(
      include(
        status: 'failed',
        attempt_kind: 'transfer',
        reason_code: 'protocol_error',
        failure_class: 'primary',
        message: 'failed while receiving responses: unexpected end of input'
      )
    )
  end

  it 'normalizes every transfer-connect network-down result' do
    log = described_class.new

    ['network down', 'host down', 'network unreachable', 'host unreachable'].each_with_index do |status, i|
      event = log.send(
        :parse_message,
        "transfer of 'network-#{i}.test/IN' from 192.0.2.1#53: Transfer status: #{status}"
      )

      expect(event).to include(
        status: 'failed',
        attempt_kind: 'transfer',
        reason_code: 'connection_failed',
        failure_class: 'network'
      )
    end
  end

  it 'classifies refresh failures by primary and suppresses nonterminal fallbacks' do
    log = described_class.new

    timeout = log.send(
      :parse_message,
      'zone refresh.test/IN: refresh: failure trying primary ' \
      '192.0.2.1#53 (source 0.0.0.0#0): timed out'
    )
    servfail = log.send(
      :parse_message,
      'zone refresh.test/IN: refresh: unexpected rcode (SERVFAIL) from ' \
      'primary 192.0.2.2#53 (source 0.0.0.0#0)'
    )
    refused = log.send(
      :parse_message,
      'zone refresh.test/IN: refresh: unexpected rcode (REFUSED) from ' \
      'primary 192.0.2.3#53 (source 0.0.0.0#0)'
    )

    expect(timeout).to include(
      attempt_kind: 'refresh',
      failure_class: 'network',
      reason_code: 'timeout',
      primary_addr: '192.0.2.1'
    )
    expect(servfail).to include(
      attempt_kind: 'refresh',
      failure_class: 'primary',
      reason_code: 'servfail',
      primary_addr: '192.0.2.2'
    )
    expect(refused).to include(
      attempt_kind: 'refresh',
      failure_class: 'primary',
      reason_code: 'refused',
      primary_addr: '192.0.2.3'
    )

    protocol_error = log.send(
      :parse_message,
      'zone refresh.test/IN: refresh: NODATA response from ' \
      'primary 192.0.2.3#53 (source 0.0.0.0#0)'
    )
    expect(protocol_error).to include(
      attempt_kind: 'refresh',
      failure_class: 'primary',
      reason_code: 'protocol_error',
      primary_addr: '192.0.2.3'
    )

    retry_limit = log.send(
      :parse_message,
      'zone refresh.test/IN: refresh: retry limit for primary ' \
      '192.0.2.1#53 exceeded (source 0.0.0.0#0)'
    )
    expect(retry_limit).to include(
      attempt_kind: 'refresh',
      failure_class: 'network',
      reason_code: 'timeout',
      primary_addr: '192.0.2.1'
    )

    [
      'zone refresh.test/IN: refresh: timeout retrying without EDNS primary ' \
      '192.0.2.1#53 (source 0.0.0.0#0)',
      'zone refresh.test/IN: refresh: truncated UDP answer, initiating TCP zone xfer ' \
      'for primary 192.0.2.1#53 (source 0.0.0.0#0)'
    ].each do |message|
      expect(log.send(:parse_message, message)).to be_nil
    end
  end

  it 'lets successful TCP fallback recover a retry-limit network failure' do
    log = described_class.new
    events = parse(
      log,
      'zone refresh-fallback.test/IN: refresh: retry limit for primary ' \
      '192.0.2.1#53 exceeded (source 0.0.0.0#0)',
      'zone refresh-fallback.test/IN: refresh: truncated UDP answer, initiating ' \
      'TCP zone xfer for primary 192.0.2.1#53 (source 0.0.0.0#0)',
      'zone refresh-fallback.test/IN: serial number (2026081308) received from ' \
      'primary 192.0.2.1#53 < ours (2026081309)'
    )

    expect(events).to contain_exactly(
      include(status: 'failed', failure_class: 'network', reason_code: 'timeout'),
      include(status: 'success', attempt_kind: 'refresh', primary_addr: '192.0.2.1')
    )
  end

  it 'retains retry-limit evidence when BIND skips TCP fallback' do
    log = described_class.new
    event = log.send(
      :parse_message,
      'zone unreachable.test/IN: refresh: retry limit for primary ' \
      '192.0.2.1#53 exceeded (source 0.0.0.0#0)'
    )

    expect(event).to include(
      name: 'unreachable.test.',
      status: 'failed',
      attempt_kind: 'refresh',
      failure_class: 'network',
      reason_code: 'timeout',
      primary_addr: '192.0.2.1'
    )
  end

  it 'ignores nonfatal MX and SRV warnings and classifies local cache failures' do
    log = described_class.new

    [
      "zone warning.test/IN: owner/MX 'mail.warning.test' has no address records (A or AAAA)",
      "zone warning.test/IN: owner/SRV 'service.warning.test' has no address records (A or AAAA)"
    ].each do |message|
      expect(log.send(:parse_message, message)).to be_nil
    end

    event = log.send(
      :parse_message,
      'zone local.test/IN: loading from master file /var/named/local.test ' \
      'failed: permission denied'
    )

    expect(event).to include(
      status: 'failed',
      attempt_kind: 'load',
      failure_class: 'local',
      reason_code: 'unknown',
      primary_addr: nil
    )
  end

  it 'emits up-to-date NOTIFY as a distinct synchronization event' do
    log = described_class.new
    event = log.send(
      :parse_message,
      'zone current.test/IN: notify from 2001:db8::1#43627: zone is up to date'
    )

    expect(event).to include(
      name: 'current.test.',
      status: 'success',
      attempt_kind: 'notify',
      failure_class: nil,
      primary_addr: '2001:db8::1',
      message: 'Zone is up to date'
    )
  end

  it 'holds the durable cursor behind unresolved managed transfer attempts' do
    Dir.mktmpdir do |dir|
      cursor_file = File.join(dir, 'dns-transfer.cursor')
      $CFG = runtime_cfg(
        vpsadmin: { node_id: 7 },
        dns_server: { transfer_log_cursor_file: cursor_file }
      )
      published = []
      log = described_class.new

      managed_zone = Struct.new(
        :id,
        :primary_transfer_generation,
        :primary_transfer_tracking_started_at,
        :user_primaries,
        :name
      ).new(
        12,
        'generation',
        0,
        [],
        'held.test.'
      )
      allow(NodeCtld::DnsConfig).to receive(:instance).and_return(
        dns_config('held.test.' => managed_zone)
      )
      allow(NodeCtld::NodeBunny).to receive(:publish_wait) do |_exchange, payload, **_opts|
        published << JSON.parse(payload)
      end

      log.send(
        :process_journal_line,
        "#{JSON.dump('__CURSOR' => 'cursor-1', 'MESSAGE' =>
          "0xabc: transfer of 'held.test/IN' from 192.0.2.1#53: connected using 192.0.2.1#53")}\n"
      )
      expect(File.exist?(cursor_file)).to be(false)

      log.send(
        :process_journal_line,
        "#{JSON.dump('__CURSOR' => 'cursor-2', '__REALTIME_TIMESTAMP' => '1778323200000000', 'MESSAGE' =>
          "0xabc: transfer of 'held.test/IN' from 192.0.2.1#53: Transfer status: REFUSED")}\n"
      )

      expect(published.length).to eq(1)
      expect(published.first.fetch('events').first).to include(
        'name' => 'held.test.',
        'status' => 'failed',
        'attempt_kind' => 'transfer',
        'failure_class' => 'primary',
        'reason_code' => 'refused',
        'dns_server_zone_id' => 12,
        'configuration_generation' => 'generation',
        'source_cursor' => 'cursor-2'
      )
      expect(File.read(cursor_file).strip).to eq('cursor-2')
    end
  end

  it 'keeps the configuration association from the start of a transfer' do
    log = described_class.new
    zone_class = Struct.new(
      :id,
      :primary_transfer_generation,
      :primary_transfer_tracking_started_at,
      :user_primaries
    )
    old_zone = zone_class.new(
      12,
      'old-generation',
      100,
      [{ 'id' => 20, 'kind' => 'user_primary', 'ip_addr' => '192.0.2.1' }]
    )
    new_zone = zone_class.new(
      12,
      'new-generation',
      110,
      [{ 'id' => 21, 'kind' => 'user_primary', 'ip_addr' => '192.0.2.1' }]
    )

    log.send(
      :parse_message,
      "0xabc: transfer of 'rotate.test/IN' from 192.0.2.1#53: connected",
      event_time: 101,
      dns_config: dns_config('rotate.test.' => old_zone)
    )
    event = log.send(
      :parse_message,
      "0xabc: transfer of 'rotate.test/IN' from 192.0.2.1#53: Transfer status: REFUSED",
      event_time: 111,
      dns_config: dns_config('rotate.test.' => new_zone)
    )

    expect(event).to include(
      dns_server_zone_id: 12,
      dns_zone_transfer_id: 20,
      configuration_generation: 'old-generation'
    )
  end

  it 'leaves a replayed pre-boundary transfer unassociated' do
    log = described_class.new
    managed_zone = Struct.new(
      :id,
      :primary_transfer_generation,
      :primary_transfer_tracking_started_at,
      :user_primaries
    ).new(
      12,
      'current-generation',
      200,
      [{ 'id' => 21, 'kind' => 'user_primary', 'ip_addr' => '192.0.2.1' }]
    )
    config = dns_config('replay.test.' => managed_zone)

    log.send(
      :parse_message,
      "0xabc: transfer of 'replay.test/IN' from 192.0.2.1#53: connected",
      event_time: 200,
      dns_config: config
    )
    event = log.send(
      :parse_message,
      "0xabc: transfer of 'replay.test/IN' from 192.0.2.1#53: Transfer status: REFUSED",
      event_time: 201,
      dns_config: config
    )

    expect(event).to include(
      dns_server_zone_id: 12,
      dns_zone_transfer_id: nil,
      configuration_generation: 'current-generation'
    )
  end

  it 'keeps correlation for a transfer within BIND maximum transfer time' do
    log = described_class.new
    now = 0
    allow(log).to receive(:monotonic_time) { now }

    expect(
      log.send(
        :parse_message,
        "0xabc: transfer of 'large.test/IN' from 192.0.2.1#53: connected using 192.0.2.1#53"
      )
    ).to be_nil

    now = 125 * 60
    expect(
      log.send(:parse_message, 'zone large.test/IN: transferred serial 2026081308')
    ).to include(
      name: 'large.test.',
      status: 'success',
      attempt_kind: 'transfer',
      primary_addr: '192.0.2.1',
      serial: 2_026_081_308
    )
  end

  it 'bounds unresolved transfer state' do
    log = described_class.new

    (described_class::MAX_TRANSFER_ATTEMPTS + 10).times do |i|
      log.send(
        :parse_message,
        "0x#{i.to_s(16)}: transfer of 'zone-#{i}.test/IN' from 192.0.2.1#53: connected"
      )
    end

    attempts = log.instance_variable_get(:@transfer_attempts)
    expect(attempts.length).to eq(described_class::MAX_TRANSFER_ATTEMPTS)
  end
end
