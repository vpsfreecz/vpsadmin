require 'libosctl'
require 'singleton'

module NodeCtld
  class VpsSshHostKeys
    include Singleton
    include OsCtl::Lib::Utils::Log
    include Utils::Libvirt

    class << self
      %i[update_vps_id update_vps_ids update_all_vps].each do |v|
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

      @update_all_queue = OsCtl::Lib::Queue.new
      @update_all_thread = Thread.new { update_all_worker }
    end

    # @param vps_id [Integer]
    def update_vps_id(vps_id)
      return unless enable?

      @update_vps_queue.insert(vps_id)
      nil
    end

    # @param vps_ids [Array<Integer>]
    def update_vps_ids(vps_ids)
      return if !enable? || vps_ids.empty?

      vps_ids.each do |vps_id|
        @update_vps_queue << vps_id
      end

      nil
    end

    def update_all_vps
      return unless enable?

      @update_all_queue << :update
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
        vps_id = @update_vps_queue.pop
        update_vps_keys(vps_id)
        sleep($CFG.get(:vps_ssh_host_keys, :update_vps_delay))
      end
    end

    def update_all_worker
      loop do
        @update_all_queue.pop(timeout: $CFG.get(:vps_ssh_host_keys, :update_all_interval))

        vps_ids = RpcClient.run(&:list_running_vps_ids)

        log(:info, "Updating ssh host keys of #{vps_ids.length} VPS")

        vps_ids.each do |vps_id|
          @update_vps_queue << vps_id
        end
      end
    end

    # @param vps_id [Integer]
    def update_vps_keys(vps_id)
      conn = LibvirtClient.new
      domain = conn.lookup_domain_by_name(vps_id.to_s)

      if domain.nil? || !domain.active?
        conn.close
        return
      end

      log(:info, "Updating keys of VPS #{vps_id}")
      t = Time.now

      begin
        keys = read_vps_keys(vps_id, domain)
      rescue StandardError => e
        log(
          :warn,
          "Unable to read ssh host keys from VPS #{vps_id}: #{e.message} (#{e.class})"
        )
        return
      ensure
        conn.close
      end

      return if keys.empty?

      NodeBunny.publish_wait(
        @exchange,
        {
          vps_id: vps_id,
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

    def read_vps_keys(vps_id, domain)
      cfg = VpsConfig.read(vps_id)
      return [] if cfg.os != 'linux'

      cmd = ['sh', '-c', 'head -n 100 /etc/ssh/ssh_host_*.pub']

      begin
        st, out, err =
          if cfg.vm_type == 'qemu_container'
            vmctexec(domain, cmd)
          else
            vmexec(domain, cmd)
          end
      rescue Libvirt::Error => e
        log(:warn, "Error occurred while reading SSH host keys from VPS #{vps_id}: #{e.message} (#{e.class})")
        return []
      end

      if st != 0 || out.nil?
        log(:warn, "Failed to read SSH keys from VPS #{vps_id}: #{err.inspect}")
        return []
      end

      write_r, write_w = IO.pipe
      ssh_r, ssh_w = IO.pipe

      # Run ssh-keygen on read key files
      ssh_pid = Process.spawn('ssh-keygen', '-l', '-f', '-', in: write_r, out: ssh_w)

      write_r.close
      ssh_w.close

      write_w.write(out)
      write_w.close

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

      Process.wait(ssh_pid)
      log(:warn, "ssh-keygen for VPS #{vps_id} exited with #{$?.exitstatus}") if $?.exitstatus != 0

      keys
    end
  end
end
