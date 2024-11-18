require 'libosctl'
require 'singleton'

module NodeCtld
  class VpsSshHostKeys
    include Singleton
    include OsCtl::Lib::Utils::Log
    include OsCtl::Lib::Utils::System
    include Utils::OsCtl

    class << self
      %i[update_vps schedule_update_vps].each do |v|
        define_method(v) do |*args, **kwargs, &block|
          instance.send(v, *args, **kwargs, &block)
        end
      end
    end

    def initialize
      return unless enable?

      @channel = NodeBunny.create_channel
      @exchange = @channel.direct(NodeBunny.exchange_name)

      @update_vps_queue = OsCtl::Lib::Queue.new
      @update_vps_thread = Thread.new { update_vps_worker }

      @update_all_thread = Thread.new { update_all_worker }
    end

    # @param vps_id [Integer]
    def update_vps(vps_id)
      return unless enable?

      @update_vps_queue.insert(vps_id)
    end

    # @param vps_id [Integer]
    # @param in_seconds [Integer, nil]
    def schedule_update_vps(vps_id, in_seconds: nil)
      return unless enable?

      in_seconds ||= $CFG.get(:vps_ssh_host_keys, :default_schedule_delay)
      log(:info, "Scheduling ssh host key update for VPS #{vps_id} in #{in_seconds}s")

      Thread.new do
        sleep(in_seconds)
        update_vps(vps_id)
      end

      nil
    end

    def enable?
      $CFG.get(:vps_ssh_host_keys, :enable)
    end

    def log_type
      'vps-host-keys'
    end

    protected

    HostKey = Struct.new(:bits, :fingerprint, :algorithm)

    def update_vps_worker
      loop do
        vps_or_id = @update_vps_queue.pop
        update_vps_keys(vps_or_id)
        sleep($CFG.get(:vps_ssh_host_keys, :update_vps_delay))
      end
    end

    def update_all_worker
      loop do
        sleep($CFG.get(:vps_ssh_host_keys, :update_all_interval))

        vps_ids = {}

        RpcClient.run do |rpc|
          rpc.list_running_vps_ids.each do |vps_id|
            vps_ids[vps_id] = true
          end
        end

        log(:info, "Updating ssh host keys of #{vps_ids.length} VPS")

        osctl_parse(%i[ct ls], vps_ids.keys, { state: 'running' }).each do |ct|
          next unless /^\d+$/ =~ ct[:id]

          osctl_ct = OsCtlContainer.new(ct)

          next unless vps_ids.has_key?(osctl_ct.vps_id)

          @update_vps_queue << osctl_ct
        end
      end
    end

    # @param ct [OsCtlContainer, Integer]
    def update_vps_keys(ct_or_id)
      ct =
        if ct_or_id.is_a?(Integer)
          OsCtlContainer.new(osctl_parse(%i[ct show], [ct_or_id]))
        else
          ct_or_id
        end

      log(:info, "Updating keys of VPS #{ct.id}")
      t = Time.now

      begin
        keys = read_vps_keys(ct)
      rescue StandardError => e
        log(
          :warn,
          "Unable to read ssh host keys from VPS #{ct.id}: #{e.message} (#{e.class})"
        )
        return
      end

      return if keys.empty?

      NodeBunny.publish_wait(
        @exchange,
        {
          vps_id: ct.vps_id,
          time: t.to_i,
          keys: keys.map do |key|
            {
              bits: key.bits,
              fingerprint: key.fingerprint,
              algorithm: key.algorithm
            }
          end
        }.to_json,
        content_type: 'application/json',
        routing_key: 'vps_ssh_host_keys'
      )
    end

    def read_vps_keys(ct)
      read_r, read_w = IO.pipe

      # Chroot into VPS rootfs and read ssh host key files
      read_pid = Process.fork do
        read_r.close
        $stdout.reopen(read_w)

        sys = OsCtl::Lib::Sys.new
        sys.chroot(ct.boot_rootfs)

        Dir.glob('/etc/ssh/ssh_host_*.pub').each do |v|
          File.open(v, 'r') do |f|
            $stdout.write(f.readline(32 * 1024))
          end
        rescue StandardError
          next
        end
      end

      read_w.close

      ssh_r, ssh_w = IO.pipe

      # Run ssh-keygen on read key files
      ssh_pid = Process.spawn('ssh-keygen', '-l', '-f', '-', in: read_r, out: ssh_w)

      read_r.close
      ssh_w.close

      keys = []

      ssh_r.each_line do |line|
        # Parse lines as:
        #   256 SHA256:AxPkTSz4jEJj3RhovDG1/sxkrj1POsWqoP61MA6lvdY user@host (ECDSA)
        #   256 SHA256:J4lVQrcjPZJbfSXI1AGVzOlwLGHhKtRnfn07CiSD6Ec no comment (ED25519)
        parts = line.strip.split
        bits, fingerprint = parts
        algo = parts.last

        keys << HostKey.new(bits.to_i, fingerprint, algo[1..-2])
      end

      ssh_r.close

      Process.wait(read_pid)
      log(:warn, "Reader for VPS #{ct.id} exited with #{$?.exitstatus}") if $?.exitstatus != 0

      Process.wait(ssh_pid)
      log(:warn, "ssh-keygen for VPS #{ct.id} exited with #{$?.exitstatus}") if $?.exitstatus != 0

      keys
    end
  end
end
