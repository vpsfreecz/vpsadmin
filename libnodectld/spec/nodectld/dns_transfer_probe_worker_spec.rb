# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'open3'
require 'rbconfig'
require 'nodectld/dns_transfer_probe_worker'

RSpec.describe NodeCtld::DnsTransferProbeWorker do
  let(:worker) { described_class.new }

  let(:job) do
    {
      'zone_name' => 'probe.example.test.',
      'primary_addr' => '192.0.2.20',
      'source_addr' => '192.0.2.10',
      'tsig_key' => nil,
      'loaded_serial' => 100,
      'probe_timeout' => 30,
      'axfr_timeout' => 600,
      'axfr_max_bytes' => 256 * 1024 * 1024,
      'force_axfr' => false
    }
  end

  def result(stdout: '', stderr: '', exitstatus: 0, limit: nil)
    described_class::CommandResult.new(stdout:, stderr:, exitstatus:, limit:)
  end

  def dns_output(rcode: 'NOERROR', serial: nil)
    ret = ";; ->>HEADER<<- opcode: QUERY, status: #{rcode}, id: 1234\n"
    ret << ";; flags: qr aa; QUERY: 1, ANSWER: #{serial ? 1 : 0}, " \
           "AUTHORITY: 0, ADDITIONAL: 0\n"
    if serial
      ret << ";; ANSWER SECTION:\n"
      ret << 'probe.example.test. 60 IN SOA ns.example.test. ' \
             'hostmaster.example.test. ' \
             "#{serial} 3600 600 86400 60\n"
    end
    ret
  end

  it 'uses a TSIG file and exact transfer source without exposing the secret in argv' do
    job['tsig_key'] = {
      'name' => 'probe-key',
      'algorithm' => 'hmac-sha256',
      'secret' => 'c3VwZXItc2VjcmV0'
    }
    worker.instance_variable_set(:@zone_name, job.fetch('zone_name'))
    worker.instance_variable_set(:@primary_addr, job.fetch('primary_addr'))
    worker.instance_variable_set(:@source_addr, job.fetch('source_addr'))
    worker.instance_variable_set(:@tsig_key, job.fetch('tsig_key'))
    worker.instance_variable_set(:@probe_timeout, job.fetch('probe_timeout'))
    command = nil
    query = nil
    key_contents = nil
    key_path = nil
    allow(worker).to receive(:run_command) do |argv, stdin_data:, **|
      command = argv
      query = stdin_data
      key_path = argv.fetch(argv.index('-k') + 1)
      key_contents = File.read(key_path)
      result(stdout: dns_output(serial: 100))
    end

    worker.send(:run_dig, 'IXFR=100', max_bytes: 1024, timeout: 30)

    expect(command).to include('+tcp', '-f', '-', '-k')
    expect(command).not_to include(
      '192.0.2.10', '@192.0.2.20', 'probe.example.test.', 'IXFR=100'
    )
    expect(query).to eq(
      "@192.0.2.20 -b 192.0.2.10 probe.example.test. IXFR=100\n"
    )
    expect(command.join(' ')).not_to include(job.dig('tsig_key', 'secret'))
    expect(key_contents).to include(
      'key "probe-key"',
      'secret "c3VwZXItc2VjcmV0"'
    )
    expect(File.exist?(key_path)).to be(false)
  end

  it 'accepts only a closed, typed and bounded worker job schema' do
    invalid_jobs = [
      job.merge('unexpected' => true),
      job.merge('source_addr' => 'not-an-address'),
      job.merge('source_addr' => '2001:db8::10'),
      job.merge('loaded_serial' => 0x1_0000_0000),
      job.merge('force_axfr' => 'yes'),
      job.merge('probe_timeout' => 61),
      job.merge('axfr_timeout' => 601),
      job.merge('axfr_max_bytes' => described_class::MAX_AXFR_BYTES + 1),
      job.merge(
        'tsig_key' => {
          'name' => 'key"; include "/etc/passwd',
          'algorithm' => 'hmac-sha256',
          'secret' => 'c2VjcmV0'
        }
      )
    ]

    invalid_jobs.each do |invalid_job|
      expect { worker.run(invalid_job) }.to raise_error(ArgumentError)
    end
  end

  it 'accepts only exact absolute command fields in the process envelope' do
    envelope = job.merge(
      'dig_command' => '/nix/store/test/bin/dig',
      'checkconf_command' => '/nix/store/test/bin/named-checkconf'
    )

    expect(described_class.extract_commands!(envelope)).to eq(
      'dig_command' => '/nix/store/test/bin/dig',
      'checkconf_command' => '/nix/store/test/bin/named-checkconf'
    )
    expect(envelope.keys).to match_array(described_class::JOB_KEYS)

    expect do
      described_class.extract_commands!(
        job.merge(
          'dig_command' => 'dig',
          'checkconf_command' => '/nix/store/test/bin/named-checkconf'
        )
      )
    end.to raise_error(ArgumentError, /absolute command path/)
  end

  it 'does not repeat rejected stdin contents in worker diagnostics' do
    secret = 'must-not-appear-in-output'
    script = File.expand_path('../../bin/vpsadmin-dns-transfer-probe', __dir__)
    library = File.expand_path('../../lib', __dir__)
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      '-I',
      library,
      script,
      stdin_data: JSON.generate(job.merge('unexpected_secret' => secret))
    )

    expect(status).not_to be_success
    expect(stderr).to include('probe worker failed')
    expect(stderr).not_to include(secret)
  end

  it 'enforces the output limit when a fast command exits before polling' do
    clean_ruby_env = { 'RUBYOPT' => nil, 'RUBYLIB' => nil }
    command_result = worker.send(
      :run_command,
      [
        clean_ruby_env,
        RbConfig.ruby,
        '--disable=gems',
        '-e',
        'STDOUT.write("x" * 4096)'
      ],
      timeout: 10,
      max_bytes: 64
    )

    expect(command_result.limit).to eq(:size)
    expect(command_result.stdout.bytesize).to eq(65)
  end

  it 'terminates a probe command at its local timeout' do
    clean_ruby_env = { 'RUBYOPT' => nil, 'RUBYLIB' => nil }
    command_result = worker.send(
      :run_command,
      [clean_ruby_env, RbConfig.ruby, '--disable=gems', '-e', 'sleep 2'],
      timeout: 0.05,
      max_bytes: 64
    )

    expect(command_result.limit).to eq(:timeout)
  end

  it 'confirms readiness with an IXFR and reports both serials' do
    allow(worker).to receive(:run_dig).and_return(
      result(stdout: dns_output(serial: 100)),
      result(stdout: dns_output(serial: 100))
    )

    expect(worker.run(job)).to include(
      status: 'success',
      attempt_kind: 'ixfr_probe',
      primary_serial: 100,
      secondary_serial: 100
    )
  end

  it 'uses the final IXFR serial and marks an older primary as stale' do
    allow(worker).to receive(:run_dig).and_return(
      result(stdout: dns_output(serial: 100)),
      result(stdout: dns_output(serial: 99))
    )

    expect(worker.run(job)).to include(
      status: 'failed',
      failure_class: 'primary',
      reason_code: 'stale',
      primary_serial: 99,
      secondary_serial: 100
    )
  end

  it 'accepts a primary that advances between the SOA and IXFR queries' do
    allow(worker).to receive(:run_dig).and_return(
      result(stdout: dns_output(serial: 99)),
      result(stdout: dns_output(serial: 100))
    )

    expect(worker.run(job)).to include(
      status: 'success',
      primary_serial: 100,
      secondary_serial: 100
    )
  end

  it 'rejects an SOA found only in a referral authority section' do
    referral = "#{dns_output};; AUTHORITY SECTION:\n" \
               'probe.example.test. 60 IN SOA ns.example.test. ' \
               'hostmaster.example.test. 100 3600 600 86400 60' \
               "\n"
    allow(worker).to receive(:run_dig).and_return(result(stdout: referral))

    expect(worker.run(job)).to include(
      status: 'failed',
      failure_class: 'primary',
      reason_code: 'protocol_error'
    )
  end

  it 'rejects a non-authoritative SOA answer' do
    answer = dns_output(serial: 100).sub('flags: qr aa;', 'flags: qr;')
    allow(worker).to receive(:run_dig).and_return(result(stdout: answer))

    expect(worker.run(job)).to include(
      status: 'failed',
      failure_class: 'primary',
      reason_code: 'not_authoritative'
    )
  end

  it 'fully validates an IXFR response with unexpected transfer records' do
    malformed_ixfr = dns_output(serial: 101)
                     .sub('ANSWER: 1', 'ANSWER: 2')
                     .concat("www.probe.example.test. 60 IN A 192.0.2.80\n")
    axfr = valid_axfr(101)
    allow(worker).to receive(:run_dig).and_return(
      result(stdout: dns_output(serial: 101)),
      result(stdout: malformed_ixfr),
      result(stdout: axfr)
    )
    allow(worker).to receive(:run_command).and_return(result)

    expect(worker.run(job)).to include(
      status: 'success',
      attempt_kind: 'axfr_probe',
      primary_serial: 101,
      secondary_serial: 100
    )
  end

  it 'falls back from unsupported IXFR and validates a complete AXFR' do
    allow(worker).to receive(:run_dig).and_return(
      result(stdout: dns_output(serial: 101)),
      result(stdout: dns_output(rcode: 'NOTIMP')),
      result(stdout: valid_axfr(101))
    )
    allow(worker).to receive(:run_command).and_return(result)

    expect(worker.run(job)).to include(
      status: 'success',
      attempt_kind: 'axfr_probe',
      primary_serial: 101
    )
  end

  it 'excludes a valid TSIG pseudo-section from zone validation' do
    axfr = valid_axfr(101) \
           + ";; TSIG PSEUDOSECTION:\n" \
             'probe-key. 0 ANY TSIG hmac-sha256. 0 300 32 signature ' \
             "1234 NOERROR 0\n"
    validated_zone = nil
    validation_config = nil
    validation_command = nil
    allow(worker).to receive(:run_dig).and_return(result(stdout: axfr))
    allow(worker).to receive(:run_command) do |argv, **|
      validation_command = argv
      validation_config = File.read(argv.last)
      zone_path = validation_config[/file "([^"]+)"/, 1]
      validated_zone = File.read(zone_path)
      result
    end

    event = worker.run(job.merge('force_axfr' => true))

    expect(event).to include(status: 'success', attempt_kind: 'axfr_probe')
    expect(validated_zone).to include('probe.example.test. 60 IN SOA', '60 IN NS')
    expect(validated_zone).not_to include('TSIG PSEUDOSECTION', '0 ANY TSIG')
    expect(validation_config).to include('zone "probe.example.test."')
    expect(validation_command).not_to include('probe.example.test.')
  end

  it 'keeps an older validated AXFR classified as stale' do
    allow(worker).to receive_messages(
      run_dig: result(stdout: valid_axfr(99)),
      run_command: result
    )

    expect(worker.run(job.merge('force_axfr' => true))).to include(
      status: 'failed',
      attempt_kind: 'axfr_probe',
      failure_class: 'primary',
      reason_code: 'stale',
      primary_serial: 99,
      secondary_serial: 100
    )
  end

  it 'distinguishes cheap network timeouts from full-transfer safeguards' do
    allow(worker).to receive(:run_dig).and_return(result(limit: :timeout))
    cheap = worker.run(job)
    full = worker.run(job.merge('force_axfr' => true))

    expect(cheap).to include(
      attempt_kind: 'ixfr_probe',
      failure_class: 'network',
      reason_code: 'timeout'
    )
    expect(full).to include(
      attempt_kind: 'axfr_probe',
      failure_class: 'local',
      reason_code: 'probe_limit'
    )
  end

  it 'classifies invalid zones and local validation limits separately' do
    allow(worker).to receive(:run_dig).and_return(
      result(stdout: valid_axfr(100)),
      result(stdout: valid_axfr(100))
    )
    allow(worker).to receive(:run_command).and_return(
      result(exitstatus: 1, stderr: 'zone has no NS records'),
      result(limit: :timeout, stderr: 'validator timed out')
    )

    invalid = worker.run(job.merge('force_axfr' => true))
    limited = worker.run(job.merge('force_axfr' => true))

    expect(invalid).to include(
      failure_class: 'primary',
      reason_code: 'invalid_zone'
    )
    expect(limited).to include(
      failure_class: 'local',
      reason_code: 'probe_limit'
    )
  end

  it 'classifies network, TSIG, ACL and local safeguard failures' do
    cases = [
      [result(stderr: 'connection timed out', exitstatus: 9), 'network', 'timeout'],
      [
        result(stderr: 'could not verify TSIG signature', exitstatus: 9),
        'primary',
        'tsig_error'
      ],
      [result(stdout: dns_output(rcode: 'REFUSED')), 'primary', 'refused'],
      [result(limit: :size, exitstatus: nil), 'local', 'probe_limit']
    ]

    cases.each do |command_result, failure_class, reason_code|
      failure = worker.send(:dig_failure, command_result, 'ixfr_probe')
      expect(failure).to include(failure_class:, reason_code:)
    end
  end

  it 'does not publish AXFR answer data in a failure diagnostic' do
    zone_data = "private.probe.example.test. 60 IN TXT \"not for logs\"\n"
    command_result = result(
      stdout: "#{dns_output}\n#{zone_data}",
      stderr: ";; Couldn't verify signature: expected a TSIG or SIG(0)"
    )

    failure = worker.send(:dig_failure, command_result, 'axfr_probe')

    expect(failure).to include(
      failure_class: 'primary',
      reason_code: 'tsig_error'
    )
    expect(failure.fetch(:message)).to include('expected a TSIG or SIG(0)')
    expect(failure.fetch(:message)).not_to include(
      'private.probe.example.test',
      'not for logs'
    )
  end

  def valid_axfr(serial)
    "#{dns_output(serial: serial)}" \
      "probe.example.test. 60 IN NS ns.example.test.\n" \
      "ns.example.test. 60 IN A 192.0.2.53\n"
  end
end
