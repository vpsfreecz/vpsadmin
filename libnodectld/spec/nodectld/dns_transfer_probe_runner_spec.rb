# frozen_string_literal: true

require 'spec_helper'
require 'rbconfig'
require 'tempfile'
require 'timeout'
require 'nodectld/dns_transfer_probe_worker'
require 'nodectld/dns_transfer_probe_runner'

RSpec.describe NodeCtld::DnsTransferProbeRunner do
  subject(:runner) { described_class.new }

  let(:job) do
    {
      'zone_name' => 'probe.example.test.',
      'primary_addr' => '192.0.2.20',
      'source_addr' => '192.0.2.10',
      'tsig_key' => nil,
      'loaded_serial' => 100,
      'force_axfr' => false,
      'probe_timeout' => 30,
      'axfr_timeout' => 600,
      'axfr_max_bytes' => 256 * 1024 * 1024
    }
  end

  def executable_script(source)
    Tempfile.new('dns-transfer-probe-runner-spec-').tap do |file|
      file.write("#!#{RbConfig.ruby}\n#{source}")
      file.flush
      file.chmod(0o700)
      file.close
    end
  end

  def runner_with_commands(systemd_run:, systemctl:)
    commands = {
      transfer_probe_systemd_run_command: systemd_run,
      transfer_probe_systemctl_command: systemctl,
      transfer_probe_worker_command: RbConfig.ruby,
      transfer_probe_dig_command: RbConfig.ruby,
      transfer_probe_checkconf_command: RbConfig.ruby
    }
    described_class.new(config_resolver: ->(key) { commands.fetch(key) })
  end

  it 'constructs a transient unprivileged service restricted to the primary' do
    command = runner.send(
      :systemd_run_command,
      job,
      'vpsadmin-dns-transfer-probe-test'
    )

    expect(command).to include(
      '--wait',
      '--pipe',
      '--collect',
      '--property=DynamicUser=yes',
      '--property=NoNewPrivileges=yes',
      '--property=ProtectSystem=strict',
      '--property=PrivateDevices=yes',
      '--property=CapabilityBoundingSet=',
      '--property=RestrictAddressFamilies=AF_INET AF_INET6',
      '--property=IPAddressDeny=any',
      '--property=IPAddressAllow=192.0.2.20',
      '--property=InaccessiblePaths=/var/named /var/lib/nodectld /etc/vpsadmin',
      '--property=RuntimeMaxSec=750',
      '--property=PartOf=vpsadmin-nodectld.service'
    )
  end

  it 'accepts a bounded result without path or broker metadata' do
    result = runner.send(
      :parse_result,
      JSON.generate(
        status: 'success',
        attempt_kind: 'ixfr_probe',
        message: 'ready',
        primary_serial: 100,
        secondary_serial: 100
      )
    )

    expect(result).to include(status: 'success', attempt_kind: 'ixfr_probe')
    expect(result.keys).not_to include(
      :dns_server_zone_id,
      :dns_zone_transfer_id,
      :configuration_generation,
      :event_key
    )
  end

  it 'rejects malformed and oversized worker results' do
    expect do
      runner.send(:parse_result, '{')
    end.to raise_error(described_class::Error, /invalid result/)

    expect do
      runner.send(
        :parse_result,
        'x' * (NodeCtld::DnsTransferProbeWorker::MAX_RESULT_BYTES + 1)
      )
    end.to raise_error(described_class::Error, /size limit/)
  end

  it 'rejects unexpected metadata from the isolated worker' do
    expect do
      runner.send(
        :parse_result,
        JSON.generate(
          status: 'success',
          attempt_kind: 'ixfr_probe',
          message: 'ready',
          dns_server_zone_id: 123
        )
      )
    end.to raise_error(described_class::Error, /invalid result/)
  end

  it 'requires the canonical bounded reason for a failure code' do
    expect do
      runner.send(
        :parse_result,
        JSON.generate(
          status: 'failed',
          attempt_kind: 'ixfr_probe',
          failure_class: 'primary',
          reason_code: 'refused',
          reason: 'x' * 256,
          message: 'refused'
        )
      )
    end.to raise_error(described_class::Error, /invalid failure result/)
  end

  it 'terminates a running service as soon as its aggregate output exceeds the cap' do
    stdout, child_stdout = IO.pipe
    stderr, child_stderr = IO.pipe
    clean_ruby_env = { 'RUBYOPT' => nil, 'RUBYLIB' => nil }
    pid = Process.spawn(
      clean_ruby_env,
      RbConfig.ruby,
      '--disable=gems',
      '-e',
      'loop { STDOUT.write("x" * 16_384); STDOUT.flush }',
      out: child_stdout,
      err: child_stderr,
      pgroup: true
    )
    child_stdout.close
    child_stderr.close
    stopped_units = []
    test_runner = described_class.new(
      unit_stopper: ->(unit_name) { stopped_units << unit_name }
    )

    expect do
      test_runner.send(
        :capture_process,
        pid,
        stdout,
        stderr,
        'vpsadmin-dns-transfer-probe-test'
      )
    end.to raise_error(described_class::Error, /output exceeds/)
    expect(stopped_units).to eq(['vpsadmin-dns-transfer-probe-test'])
    Process.waitpid(pid)
  ensure
    stdout&.close
    child_stdout&.close
    stderr&.close
    child_stderr&.close
    begin
      Process.kill('KILL', pid) if pid
    rescue Errno::ESRCH
      nil
    end
    begin
      Process.waitpid(pid) if pid
    rescue Errno::ECHILD
      nil
    end
  end

  it 'does not retain a cancellation token after a unit has completed' do
    runner.send(:prepare, 'completed')
    runner.instance_variable_get(:@processes).delete('completed')
    runner.cancel('completed')

    expect(runner.instance_variable_get(:@cancelled)).to be_empty
  end

  it 'releases a prepared unit that is cancelled before launch' do
    unit_name = 'vpsadmin-dns-transfer-probe-prelaunch'
    stopped_units = []
    test_runner = described_class.new(
      unit_stopper: ->(name) { stopped_units << name }
    )
    test_runner.prepare(unit_name)

    test_runner.cancel(unit_name)
    test_runner.release(unit_name)

    expect(stopped_units).to eq([unit_name])
    expect(test_runner.instance_variable_get(:@processes)).to be_empty
    expect(test_runner.instance_variable_get(:@cancelled)).to be_empty
  end

  it 'passes a validated job on stdin and accepts one bounded result on stdout' do
    service = executable_script(<<~RUBY)
      require 'json'
      job = JSON.parse($stdin.read)
      abort 'missing exact command envelope' unless job.keys.sort == %w[
        axfr_max_bytes axfr_timeout checkconf_command dig_command force_axfr
        loaded_serial primary_addr probe_timeout source_addr tsig_key zone_name
      ].sort
      puts JSON.generate(
        status: 'success',
        attempt_kind: 'ixfr_probe',
        message: 'ready',
        primary_serial: 100,
        secondary_serial: 100
      )
    RUBY
    systemctl = executable_script('exit 0')
    test_runner = runner_with_commands(
      systemd_run: service.path,
      systemctl: systemctl.path
    )

    expect(
      test_runner.run(job, unit_name: 'vpsadmin-dns-transfer-probe-test')
    ).to include(status: 'success', primary_serial: 100)
  ensure
    service&.close!
    systemctl&.close!
  end

  it 'cancels a service that is running before it returns a result' do
    service = executable_script('$stdin.read; sleep 10')
    systemctl = executable_script('exit 0')
    test_runner = runner_with_commands(
      systemd_run: service.path,
      systemctl: systemctl.path
    )
    unit_name = 'vpsadmin-dns-transfer-probe-cancel'
    test_runner.prepare(unit_name)
    result = Queue.new
    thread = Thread.new do
      test_runner.run(job, unit_name:)
    rescue StandardError => e
      result << e
    end
    Timeout.timeout(5) do
      processes = test_runner.instance_variable_get(:@processes)
      sleep(0.01) until processes[unit_name].is_a?(Integer)
    end

    test_runner.cancel(unit_name)
    thread.join(5)

    expect(thread).not_to be_alive
    expect(result.size).to eq(1)
    expect(result.pop(true)).to be_a(described_class::Cancelled)
  ensure
    thread&.kill
    thread&.join
    service&.close!
    systemctl&.close!
  end

  it 'reports a transient-service launch failure without running a worker' do
    test_runner = runner_with_commands(
      systemd_run: '/does/not/exist/systemd-run',
      systemctl: '/does/not/exist/systemctl'
    )

    expect do
      test_runner.run(job, unit_name: 'vpsadmin-dns-transfer-probe-missing')
    end.to raise_error(described_class::Error, /unable to start probe service/)
  end
end
