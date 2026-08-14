require 'json'
require 'nodectld/dns_transfer_probe_worker'

module NodeCtld
  class DnsTransferProbeRunner
    class Error < StandardError; end
    class Cancelled < Error; end

    MAX_CAPTURE_BYTES = 128 * 1024
    RESULT_STATUSES = %w[success failed].freeze
    ATTEMPT_KINDS = %w[ixfr_probe axfr_probe].freeze
    FAILURE_CLASSES = %w[network primary local].freeze
    RESULT_KEYS = %w[
      status
      attempt_kind
      failure_class
      reason_code
      reason
      message
      primary_serial
      secondary_serial
    ].freeze

    def initialize(config_resolver: nil, unit_stopper: nil)
      @mutex = Mutex.new
      @processes = {}
      @cancelled = {}
      @config_resolver = config_resolver
      @unit_stopper = unit_stopper
    end

    def prepare(unit_name)
      @mutex.synchronize { @processes[unit_name] = nil }
    end

    def release(unit_name)
      @mutex.synchronize do
        @processes.delete(unit_name)
        @cancelled.delete(unit_name)
      end
    end

    def run(job, unit_name:)
      envelope = job.merge(
        'dig_command' => config(:transfer_probe_dig_command),
        'checkconf_command' => config(:transfer_probe_checkconf_command)
      )
      DnsTransferProbeWorker.validate_job!(job)
      DnsTransferProbeWorker.extract_commands!(envelope.dup)
      payload = JSON.generate(envelope)
      if payload.bytesize > DnsTransferProbeWorker::MAX_JOB_BYTES
        raise Error, 'probe job exceeds the local size limit'
      end

      input, output = IO.pipe
      stdout, child_stdout = IO.pipe
      stderr, child_stderr = IO.pipe
      pid = @mutex.synchronize do
        @processes[unit_name] = nil unless @processes.has_key?(unit_name)
        if @cancelled.delete(unit_name)
          raise Cancelled, 'probe path was removed'
        end

        Process.spawn(
          *systemd_run_command(job, unit_name),
          in: input,
          out: child_stdout,
          err: child_stderr,
          pgroup: true
        ).tap { |v| @processes[unit_name] = v }
      end
      input.close
      child_stdout.close
      child_stderr.close
      output.write(payload)
      output.close
      stdout_value, stderr_value, status = capture_process(
        pid, stdout, stderr, unit_name
      )

      if cancelled?(unit_name)
        raise Cancelled, 'probe path was removed'
      end
      unless status.success?
        raise Error, "probe service failed: #{safe_diagnostic(stderr_value)}"
      end

      parse_result(stdout_value)
    rescue Errno::ENOENT, Errno::EPIPE => e
      raise Error, "unable to start probe service: #{e.message}"
    ensure
      if pid && status.nil?
        terminate_process(unit_name, pid)
        begin
          Process.waitpid(pid)
        rescue Errno::ECHILD
          nil
        end
      end
      release(unit_name)
      input&.close
      output&.close
      stdout&.close
      child_stdout&.close
      stderr&.close
      child_stderr&.close
    end

    def cancel(unit_name)
      pid = @mutex.synchronize do
        return unless @processes.has_key?(unit_name)

        @cancelled[unit_name] = true
        @processes[unit_name]
      end
      terminate_process(unit_name, pid)
    rescue Errno::ENOENT, Errno::ECHILD
      nil
    end

    protected

    def systemd_run_command(job, unit_name)
      primary_addr = job.fetch('primary_addr')
      runtime = (
        job.fetch('axfr_timeout') + (2 * job.fetch('probe_timeout')) + 90
      ).ceil

      [
        config(:transfer_probe_systemd_run_command),
        '--quiet',
        '--wait',
        '--pipe',
        '--collect',
        "--unit=#{unit_name}",
        '--service-type=exec',
        '--property=DynamicUser=yes',
        '--property=PrivateTmp=yes',
        '--property=UMask=0077',
        '--property=NoNewPrivileges=yes',
        '--property=ProtectSystem=strict',
        '--property=ProtectHome=yes',
        '--property=PrivateDevices=yes',
        '--property=ProtectKernelTunables=yes',
        '--property=ProtectKernelModules=yes',
        '--property=ProtectControlGroups=yes',
        '--property=ProtectProc=invisible',
        '--property=ProcSubset=pid',
        '--property=RestrictSUIDSGID=yes',
        '--property=RestrictRealtime=yes',
        '--property=RestrictNamespaces=yes',
        '--property=LockPersonality=yes',
        '--property=CapabilityBoundingSet=',
        '--property=RestrictAddressFamilies=AF_INET AF_INET6',
        '--property=IPAddressDeny=any',
        "--property=IPAddressAllow=#{primary_addr}",
        '--property=InaccessiblePaths=/var/named /var/lib/nodectld /etc/vpsadmin',
        '--property=WorkingDirectory=/tmp',
        "--property=RuntimeMaxSec=#{runtime}",
        '--property=TasksMax=16',
        '--property=MemoryMax=768M',
        '--property=LimitNOFILE=64',
        '--property=PartOf=vpsadmin-nodectld.service',
        '--',
        config(:transfer_probe_worker_command)
      ]
    end

    def capture_process(pid, stdout, stderr, unit_name)
      values = { stdout => ''.b, stderr => ''.b }
      readers = values.keys
      status = nil

      until status && readers.empty?
        IO.select(readers, nil, nil, 0.05)&.first&.each do |io|
          chunk = io.read_nonblock(16 * 1024, exception: false)
          if chunk.nil?
            readers.delete(io)
            next
          elsif chunk == :wait_readable
            next
          end

          values.fetch(io) << chunk
          if values.values.sum(&:bytesize) > MAX_CAPTURE_BYTES
            terminate_process(unit_name, pid)
            raise Error, 'probe service output exceeds the local size limit'
          end
        end

        next if status

        _waited_pid, status = Process.waitpid2(pid, Process::WNOHANG)
      end

      [values.fetch(stdout), values.fetch(stderr), status]
    end

    def terminate_process(unit_name, pid)
      begin
        Process.kill('TERM', pid) if pid
      rescue Errno::ESRCH
        nil
      end
      stop_unit(unit_name)
    end

    def stop_unit(unit_name)
      return @unit_stopper.call(unit_name) if @unit_stopper

      pid = Process.spawn(
        config(:transfer_probe_systemctl_command),
        'stop',
        "#{unit_name}.service",
        out: File::NULL,
        err: File::NULL
      )
      Process.waitpid(pid)
    rescue Errno::ENOENT, Errno::ECHILD
      nil
    end

    def cancelled?(unit_name)
      @mutex.synchronize { @cancelled[unit_name] }
    end

    def parse_result(output)
      if output.bytesize > DnsTransferProbeWorker::MAX_RESULT_BYTES
        raise Error, 'probe result exceeds the local size limit'
      end

      result = JSON.parse(output)
      validate_result(result)
      result.transform_keys(&:to_sym)
    rescue JSON::ParserError
      raise Error, 'probe service returned an invalid result'
    end

    def validate_result(result)
      unless result.is_a?(Hash) && RESULT_STATUSES.include?(result['status']) &&
             ATTEMPT_KINDS.include?(result['attempt_kind']) &&
             valid_result_text?(result['message']) &&
             (result.keys - RESULT_KEYS).empty? &&
             valid_serial?(result['primary_serial']) &&
             valid_serial?(result['secondary_serial'])
        raise Error, 'probe service returned an invalid result'
      end

      if result['status'] == 'success'
        if result.keys.intersect?(%w[failure_class reason_code reason])
          raise Error, 'probe service returned an invalid success result'
        end

        return
      end

      unless FAILURE_CLASSES.include?(result['failure_class']) &&
             DnsTransferProbeWorker::REASON_TEXT.has_key?(result['reason_code']) &&
             result['reason'] == DnsTransferProbeWorker::REASON_TEXT.fetch(
               result['reason_code']
             )
        raise Error, 'probe service returned an invalid failure result'
      end
    end

    def valid_result_text?(value)
      value.is_a?(String) &&
        value.bytesize <= DnsTransferProbeWorker::MAX_DIAGNOSTIC_BYTES + 256
    end

    def valid_serial?(value)
      value.nil? || (value.is_a?(Integer) && value.between?(0, 0xffff_ffff))
    end

    def safe_diagnostic(value)
      value.to_s
           .encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
           .gsub(/[[:cntrl:]&&[^\n\t]]/, '?')
           .strip
           .byteslice(0, DnsTransferProbeWorker::MAX_DIAGNOSTIC_BYTES)
           .to_s
           .scrub('?')
    end

    def config(key)
      return @config_resolver.call(key) if @config_resolver

      $CFG.get(:dns_server, key)
    end
  end
end
