require 'libosctl'
require 'singleton'

module NodeCtld
  class VpsSshHostKeys
    include Singleton
    include OsCtl::Lib::Utils::Log
    include OsCtl::Lib::Utils::System
    include Utils::OsCtl

    class << self
      %i(update_vps, schedule_update_vps).each do |v|
        define_method(v) do |*args, **kwargs, &block|
          instance.send(v, *args, **kwargs, &block)
        end
      end
    end

    def initialize
      return unless enable?

      @channel = NodeBunny.create_channel
      @exchange = @channel.direct('node:vps_ssh_host_keys')

      @update_vps_queue = OsCtl::Lib::Queue.new
      @update_vps_thread = Thread.new { update_vps_worker }

      @update_all_thread = Thread.new { update_all_worker }
    end

    # @param vps_id [Integer]
    def update_vps(vps_id)
      return unless enable?

      @update_vps_queue.insert(VpsUpdate.new(vps_id, nil))
    end

    # @param vps_id [Integer]
    # @param in_seconds [Integer, nil]
    def schedule_update_vps(vps_id, in_seconds = nil)
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
    VpsUpdate = Struct.new(:id, :boot_rootfs)

    HostKey = Struct.new(:bits, :fingerprint, :algorithm)

    def update_vps_worker
      loop do
        vps = @update_vps_queue.pop
        update_vps_keys(vps)
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

        osctl_parse(%i(ct ls), vps_ids.keys, {state: 'running'}).each do |ct|
          next unless /^\d+$/ =~ ct[:id]

          vps_id = ct[:id].to_i
          next unless vps_ids.has_key?(vps_id)

          @update_vps_queue << VpsUpdate.new(vps_id, ct[:boot_rootfs])
        end
      end
    end

    # @param vps [VpsUpdate]
    def update_vps_keys(vps)
      log(:info, "Updating keys of VPS #{vps.id}")
      vps.boot_rootfs ||= osctl_parse(%i(ct show), [vps.id])[:boot_rootfs]
      t = Time.now

      begin
        keys = read_vps_keys(vps)
      rescue => e
        log(
          :warn,
          "Unable to read ssh host keys from VPS #{vps.id}: #{e.message} (#{e.class})"
        )
        return
      end

      return if keys.empty?

      @exchange.publish(
        {
          vps_id: vps.id,
          time: t.to_i,
          keys: keys.map do |key|
            {
              bits: key.bits,
              fingerprint: key.fingerprint,
              algorithm: key.algorithm,
            }
          end,
        }.to_json,
        content_type: 'application/json',
        routing_key: $CFG.get(:vpsadmin, :routing_key),
      )
    end

    def read_vps_keys(vps)
      read_r, read_w = IO.pipe

      # Chroot into VPS rootfs and read ssh host key files
      read_pid = Process.fork do
        read_r.close
        STDOUT.reopen(read_w)

        sys = OsCtl::Lib::Sys.new
        sys.chroot(vps.boot_rootfs)

        Dir.glob('/etc/ssh/ssh_host_*.pub').each do |v|
          begin
            File.open(v, 'r') do |f|
              STDOUT.write(f.readline(32*1024))
            end
          rescue
            next
          end
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
      if $?.exitstatus != 0
        log(:warn, "Reader for VPS #{vps.id} exited with #{$?.exitstatus}")
      end

      Process.wait(ssh_pid)
      if $?.exitstatus != 0
        log(:warn, "ssh-keygen for VPS #{vps.id} exited with #{$?.exitstatus}")
      end

      keys
    end
  end
end
