# frozen_string_literal: true

require 'spec_helper'
require 'rbconfig'
require 'nodectld/queues'
require 'nodectld/dns_config'
require 'nodectld/dns_server_zone'
require 'nodectld/dns_transfer_probe'

RSpec.describe NodeCtld::DnsTransferProbe do
  let(:probe) do
    stub_node_bunny
    described_class.new
  end
  let(:zone) do
    NodeCtld::DnsServerZone.new(
      id: 10,
      name: 'probe.example.test.',
      source: 'external_source',
      type: 'secondary_type',
      enabled: true,
      primaries: [primary],
      secondaries: [],
      primary_transfer_generation: 'generation',
      primary_transfer_tracking_started_at: Time.now.to_i - 60,
      probe_source_addrs: {
        'ipv4' => '192.0.2.10',
        'ipv6' => '2001:db8::10'
      },
      load_db: false
    ).tap { |v| v.loaded_serial = 100 }
  end
  let(:primary) do
    {
      'id' => 20,
      'kind' => 'user_primary',
      'ip_addr' => '192.0.2.20',
      'tsig_key' => nil
    }
  end
  let(:probe_tmpdir) { Dir.mktmpdir('dns-transfer-probe-spec') }

  before do
    $CFG.patch(
      dns_server: {
        transfer_probe_state_file: File.join(probe_tmpdir, 'state.json')
      }
    )
  end

  after do
    described_class.instance = nil
    FileUtils.rm_rf(probe_tmpdir)
  end

  def result(stdout: '', stderr: '', exitstatus: 0, limit: nil)
    described_class::CommandResult.new(stdout:, stderr:, exitstatus:, limit:)
  end

  def dns_output(rcode: 'NOERROR', serial: nil)
    ret = ";; ->>HEADER<<- opcode: QUERY, status: #{rcode}, id: 1234\n"
    ret << ";; flags: qr aa; QUERY: 1, ANSWER: #{serial ? 1 : 0}, AUTHORITY: 0, ADDITIONAL: 0\n"
    if serial
      ret << ";; ANSWER SECTION:\n"
      ret << 'probe.example.test. 60 IN SOA ns.example.test. hostmaster.example.test. ' \
             "#{serial} 3600 600 86400 60\n"
    end
    ret
  end

  it 'uses a TSIG file and exact transfer source without exposing the secret in argv' do
    primary['tsig_key'] = {
      'name' => 'probe-key',
      'algorithm' => 'hmac-sha256',
      'secret' => 'c3VwZXItc2VjcmV0'
    }
    command = nil
    key_contents = nil
    key_path = nil
    allow(probe).to receive(:run_command) do |argv, **|
      command = argv
      key_path = argv.fetch(argv.index('-k') + 1)
      key_contents = File.read(key_path)
      result(stdout: dns_output(serial: 100))
    end

    probe.send(
      :run_dig,
      zone,
      primary,
      '192.0.2.10',
      'IXFR=100',
      max_bytes: 1024,
      timeout: 30
    )

    expect(command).to include('+tcp', '-b', '192.0.2.10', '@192.0.2.20', 'IXFR=100', '-k')
    expect(command.join(' ')).not_to include(primary.dig('tsig_key', 'secret'))
    expect(key_contents).to include('key "probe-key"', 'secret "c3VwZXItc2VjcmV0"')
    expect(File.exist?(key_path)).to be(false)
  end

  it 'enforces the output limit when a fast command exits before the next poll' do
    clean_ruby_env = { 'RUBYOPT' => nil, 'RUBYLIB' => nil }
    command_result = probe.send(
      :run_command,
      [clean_ruby_env, RbConfig.ruby, '--disable=gems', '-e', 'STDOUT.write("x" * 4096)'],
      timeout: 10,
      max_bytes: 64
    )

    expect(command_result.limit).to eq(:size)
    expect(command_result.stdout.bytesize).to eq(65)
  end

  it 'terminates a probe command at its local timeout' do
    clean_ruby_env = { 'RUBYOPT' => nil, 'RUBYLIB' => nil }
    command_result = probe.send(
      :run_command,
      [clean_ruby_env, RbConfig.ruby, '--disable=gems', '-e', 'sleep 2'],
      timeout: 0.05,
      max_bytes: 64
    )

    expect(command_result.limit).to eq(:timeout)
  end

  it 'confirms readiness with a signed IXFR and reports both serials' do
    allow(probe).to receive(:run_dig).and_return(
      result(stdout: dns_output(serial: 100)),
      result(stdout: dns_output(serial: 100))
    )

    event = probe.send(:probe, zone, primary)

    expect(event).to include(
      status: 'success',
      attempt_kind: 'ixfr_probe',
      dns_server_zone_id: 10,
      dns_zone_transfer_id: 20,
      configuration_generation: 'generation',
      primary_serial: 100,
      secondary_serial: 100
    )
  end

  it 'marks a reachable older primary as stale' do
    allow(probe).to receive(:run_dig).and_return(
      result(stdout: dns_output(serial: 99)),
      result(stdout: dns_output(serial: 99))
    )

    event = probe.send(:probe, zone, primary)

    expect(event).to include(
      status: 'failed',
      failure_class: 'primary',
      reason_code: 'stale',
      primary_serial: 99,
      secondary_serial: 100
    )
  end

  it 'uses the final authenticated IXFR serial when the primary changes' do
    allow(probe).to receive(:run_dig).and_return(
      result(stdout: dns_output(serial: 100)),
      result(stdout: dns_output(serial: 99))
    )

    event = probe.send(:probe, zone, primary)

    expect(event).to include(
      status: 'failed',
      failure_class: 'primary',
      reason_code: 'stale',
      primary_serial: 99,
      secondary_serial: 100
    )
  end

  it 'accepts a primary that advances between the SOA and IXFR queries' do
    allow(probe).to receive(:run_dig).and_return(
      result(stdout: dns_output(serial: 99)),
      result(stdout: dns_output(serial: 100))
    )

    event = probe.send(:probe, zone, primary)

    expect(event).to include(
      status: 'success',
      primary_serial: 100,
      secondary_serial: 100
    )
  end

  it 'rejects an SOA found only in a referral authority section' do
    referral = "#{dns_output};; AUTHORITY SECTION:\n" \
               'probe.example.test. 60 IN SOA ns.example.test. hostmaster.example.test. ' \
               "100 3600 600 86400 60\n"
    allow(probe).to receive(:run_dig).and_return(result(stdout: referral))

    event = probe.send(:probe, zone, primary)

    expect(event).to include(
      status: 'failed',
      failure_class: 'primary',
      reason_code: 'protocol_error'
    )
  end

  it 'rejects a non-authoritative SOA answer' do
    answer = dns_output(serial: 100).sub('flags: qr aa;', 'flags: qr;')
    allow(probe).to receive(:run_dig).and_return(result(stdout: answer))

    event = probe.send(:probe, zone, primary)

    expect(event).to include(
      status: 'failed',
      failure_class: 'primary',
      reason_code: 'not_authoritative'
    )
  end

  it 'fully validates an IXFR response whose SOA is only in the authority section' do
    referral = "#{dns_output};; AUTHORITY SECTION:\n" \
               'probe.example.test. 60 IN SOA ns.example.test. hostmaster.example.test. ' \
               "100 3600 600 86400 60\n"
    axfr = "#{dns_output(serial: 100)}" \
           "probe.example.test. 60 IN NS ns.example.test.\n" \
           "ns.example.test. 60 IN A 192.0.2.53\n"
    allow(probe).to receive(:run_dig).and_return(
      result(stdout: dns_output(serial: 100)),
      result(stdout: referral),
      result(stdout: axfr)
    )
    allow(probe).to receive(:run_command).and_return(result)

    event = probe.send(:probe, zone, primary)

    expect(event).to include(
      status: 'success',
      attempt_kind: 'axfr_probe'
    )
  end

  it 'reports a cheap-query timeout as a network failure' do
    allow(probe).to receive(:run_dig).and_return(result(limit: :timeout))

    event = probe.send(:probe, zone, primary)

    expect(event).to include(
      status: 'failed',
      attempt_kind: 'ixfr_probe',
      failure_class: 'network',
      reason_code: 'timeout'
    )
  end

  it 'reports a full-transfer timeout as an inconclusive local safeguard' do
    allow(probe).to receive(:run_dig).and_return(result(limit: :timeout))

    event = probe.send(:probe, zone, primary, force_axfr: true)

    expect(event).to include(
      status: 'failed',
      attempt_kind: 'axfr_probe',
      failure_class: 'local',
      reason_code: 'probe_limit'
    )
  end

  it 'fully validates an IXFR response with unexpected transfer records' do
    malformed_ixfr = dns_output(serial: 101)
                     .sub('ANSWER: 1', 'ANSWER: 2')
                     .concat("www.probe.example.test. 60 IN A 192.0.2.80\n")
    axfr = "#{dns_output(serial: 101)}" \
           "probe.example.test. 60 IN NS ns.example.test.\n" \
           "ns.example.test. 60 IN A 192.0.2.53\n"
    allow(probe).to receive(:run_dig).and_return(
      result(stdout: dns_output(serial: 101)),
      result(stdout: malformed_ixfr),
      result(stdout: axfr)
    )
    allow(probe).to receive(:run_command).and_return(result)

    event = probe.send(:probe, zone, primary)

    expect(event).to include(
      status: 'success',
      attempt_kind: 'axfr_probe',
      primary_serial: 101,
      secondary_serial: 100
    )
  end

  it 'falls back from unsupported IXFR and validates a complete AXFR' do
    axfr = "#{dns_output(serial: 101)}" \
           "probe.example.test. 60 IN NS ns.example.test.\n" \
           "ns.example.test. 60 IN A 192.0.2.53\n"
    allow(probe).to receive(:run_dig).and_return(
      result(stdout: dns_output(serial: 101)),
      result(stdout: dns_output(rcode: 'NOTIMP')),
      result(stdout: axfr)
    )
    allow(probe).to receive(:run_command).and_return(result)

    event = probe.send(:probe, zone, primary)

    expect(event).to include(
      status: 'success',
      attempt_kind: 'axfr_probe',
      primary_serial: 101
    )
    expect(probe).to have_received(:run_command).with(
      include('named-checkzone', '-q', zone.name),
      timeout: 60,
      max_bytes: 256 * 1024
    )
  end

  it 'excludes a valid TSIG pseudo-section from zone validation' do
    axfr = "#{dns_output(serial: 101)}" \
           "probe.example.test. 60 IN NS ns.example.test.\n" \
           "ns.example.test. 60 IN A 192.0.2.53\n" \
           ";; TSIG PSEUDOSECTION:\n" \
           "probe-key. 0 ANY TSIG hmac-sha256. 0 300 32 signature 1234 NOERROR 0\n"
    validated_zone = nil
    allow(probe).to receive(:run_dig).and_return(result(stdout: axfr))
    allow(probe).to receive(:run_command) do |argv, **|
      validated_zone = File.read(argv.last)
      result
    end

    event = probe.send(:probe, zone, primary, force_axfr: true)

    expect(event).to include(status: 'success', attempt_kind: 'axfr_probe')
    expect(validated_zone).to include('probe.example.test. 60 IN SOA', '60 IN NS')
    expect(validated_zone).not_to include('TSIG PSEUDOSECTION', '0 ANY TSIG')
  end

  it 'keeps an older validated AXFR classified as stale' do
    axfr = "#{dns_output(serial: 99)}" \
           "probe.example.test. 60 IN NS ns.example.test.\n" \
           "ns.example.test. 60 IN A 192.0.2.53\n"
    allow(probe).to receive_messages(
      run_dig: result(stdout: axfr),
      run_command: result
    )

    event = probe.send(:probe, zone, primary, force_axfr: true)

    expect(event).to include(
      status: 'failed',
      attempt_kind: 'axfr_probe',
      failure_class: 'primary',
      reason_code: 'stale',
      primary_serial: 99,
      secondary_serial: 100
    )
  end

  it 'reports zone validation failures as primary content errors' do
    allow(probe).to receive_messages(
      run_dig: result(stdout: dns_output(serial: 100)),
      run_command: result(exitstatus: 1, stderr: 'zone has no NS records')
    )

    event = probe.send(:probe, zone, primary, force_axfr: true)

    expect(event).to include(
      status: 'failed',
      attempt_kind: 'axfr_probe',
      failure_class: 'primary',
      reason_code: 'invalid_zone'
    )
  end

  it 'keeps local zone-validation limits out of user-facing failures' do
    allow(probe).to receive_messages(
      run_dig: result(stdout: dns_output(serial: 100)),
      run_command: result(limit: :timeout, stderr: 'validator timed out')
    )

    event = probe.send(:probe, zone, primary, force_axfr: true)

    expect(event).to include(
      status: 'failed',
      attempt_kind: 'axfr_probe',
      failure_class: 'local',
      reason_code: 'probe_limit'
    )
  end

  it 'classifies network, TSIG, ACL and local safeguard failures separately' do
    cases = [
      [result(stderr: 'connection timed out', exitstatus: 9), 'network', 'timeout'],
      [result(stderr: 'could not verify TSIG signature', exitstatus: 9), 'primary', 'tsig_error'],
      [
        result(
          stdout: dns_output,
          stderr: ";; Couldn't verify signature: expected a TSIG or SIG(0)",
          exitstatus: 0
        ),
        'primary',
        'tsig_error'
      ],
      [result(stdout: dns_output(rcode: 'REFUSED'), exitstatus: 0), 'primary', 'refused'],
      [result(limit: :size, exitstatus: nil), 'local', 'probe_limit']
    ]

    cases.each do |command_result, failure_class, reason_code|
      event = probe.send(:dig_failure, zone, primary, command_result, 'ixfr_probe')
      expect(event).to include(failure_class:, reason_code:)
    end
  end

  it 'does not mistake a valid TSIG pseudo-section for a verification failure' do
    command_result = result(
      stdout: "#{dns_output}\n;; TSIG PSEUDOSECTION:\n" \
              "probe-key. 0 ANY TSIG hmac-sha256. 0 300 32 signature 1234 NOERROR 0\n"
    )

    expect(probe.send(:dig_failure, zone, primary, command_result, 'ixfr_probe')).to be_nil
  end

  it 'does not publish AXFR answer data in a failure diagnostic' do
    zone_data = "private.probe.example.test. 60 IN TXT \"not for logs\"\n"
    command_result = result(
      stdout: "#{dns_output}\n#{zone_data}",
      stderr: ";; Couldn't verify signature: expected a TSIG or SIG(0)",
      exitstatus: 0
    )

    event = probe.send(:dig_failure, zone, primary, command_result, 'axfr_probe')

    expect(event).to include(failure_class: 'primary', reason_code: 'tsig_error')
    expect(event.fetch(:message)).to include('expected a TSIG or SIG(0)')
    expect(event.fetch(:message)).not_to include('private.probe.example.test', 'not for logs')
    expect(event.fetch(:message).bytesize).to be <= described_class::MAX_DIAGNOSTIC_BYTES + 64
  end

  it 'does not classify zone contents as dig diagnostics' do
    command_result = result(
      stdout: "#{dns_output(serial: 100)}" \
              "text.probe.example.test. 60 IN TXT \"signature failed for old client\"\n"
    )

    expect(probe.send(:dig_failure, zone, primary, command_result, 'axfr_probe')).to be_nil
  end

  it 'uses deterministic staggering and bounded failure retry intervals' do
    first_delay = probe.send(:initial_delay, '10:20:generation')
    second_delay = probe.send(:initial_delay, '10:20:generation')
    expect(first_delay).to eq(second_delay)
    expect(first_delay).to be >= 60
    expect(first_delay).to be <= 3599
    expect(probe.send(:next_interval, status: 'failed', failure_class: 'network')).to eq(300)
    expect(
      probe.send(
        :next_interval,
        status: 'failed',
        failure_class: 'primary',
        reason_code: 'refused'
      )
    ).to eq(300)
    expect(
      probe.send(
        :next_interval,
        status: 'failed',
        failure_class: 'primary',
        reason_code: 'invalid_zone'
      )
    ).to eq(3600)
    expect(
      probe.send(
        :next_interval,
        status: 'failed',
        failure_class: 'primary',
        reason_code: 'protocol_error'
      )
    ).to eq(3600)
    expect(
      probe.send(
        :next_interval,
        status: 'failed',
        failure_class: 'primary',
        reason_code: 'stale'
      )
    ).to eq(3600)
    expect(probe.send(:next_interval, status: 'success', failure_class: nil)).to eq(3600)

    5.times { |i| probe.instance_variable_get(:@running)[i.to_s] = instance_double(Thread) }
    expect(probe.send(:available_slots)).to eq(0)
  end

  it 'schedules every configured user primary and ignores vpsAdmin peers' do
    second_primary = primary.merge('id' => 21, 'ip_addr' => '192.0.2.21')
    peer = primary.merge('id' => 30, 'kind' => 'vpsadmin_peer', 'ip_addr' => '192.0.2.30')
    zone.primaries.push(second_primary, peer)
    allow(NodeCtld::DnsConfig).to receive(:instance).and_return(
      instance_double(NodeCtld::DnsConfig, zones: [zone])
    )

    expect(probe.send(:probe_paths)).to contain_exactly(
      [zone, primary],
      [zone, second_primary]
    )
  end

  it 'keeps an immediate follow-up requested while another probe is running' do
    key = probe.send(:path_key, zone, primary)
    pending_at = Time.now.to_f
    probe.instance_variable_get(:@schedule)[key] = pending_at
    allow(probe).to receive(:probe).and_return(
      status: 'success',
      attempt_kind: 'ixfr_probe',
      failure_class: nil
    )
    allow(probe).to receive(:publish)

    probe.send(:run_scheduled_probe, key, zone, primary)

    expect(probe.instance_variable_get(:@schedule)[key]).to eq(pending_at)
  end

  it 'retries failed AXFR validation after a nodectld restart' do
    key = probe.send(:path_key, zone, primary)
    allow(probe).to receive(:probe).and_return(
      status: 'failed',
      attempt_kind: 'axfr_probe',
      failure_class: 'primary',
      reason_code: 'invalid_zone'
    )
    allow(probe).to receive(:publish)

    probe.send(:run_scheduled_probe, key, zone, primary)

    restarted_probe = described_class.new
    expect(restarted_probe.send(:needs_axfr?, key)).to be(true)
  end

  it 'keeps full-validation recovery latched across generation rotation' do
    old_key = probe.send(:path_key, zone, primary)
    allow(probe).to receive(:probe).and_return(
      status: 'failed',
      attempt_kind: 'axfr_probe',
      failure_class: 'primary',
      reason_code: 'invalid_zone'
    )
    allow(probe).to receive(:publish)

    probe.send(:run_scheduled_probe, old_key, zone, primary)
    zone.instance_variable_set(:@primary_transfer_generation, 'next-generation')
    new_key = probe.send(:path_key, zone, primary)

    restarted_probe = described_class.new
    expect(restarted_probe.send(:needs_axfr?, new_key)).to be(true)
  end

  it 'persists the AXFR requirement before publishing the failure' do
    key = probe.send(:path_key, zone, primary)
    allow(probe).to receive(:probe).and_return(
      status: 'failed',
      attempt_kind: 'axfr_probe',
      failure_class: 'primary',
      reason_code: 'invalid_zone'
    )
    allow(probe).to receive(:publish).and_raise('broker unavailable')

    probe.send(:run_scheduled_probe, key, zone, primary)

    restarted_probe = described_class.new
    expect(restarted_probe.send(:needs_axfr?, key)).to be(true)
  end
end
