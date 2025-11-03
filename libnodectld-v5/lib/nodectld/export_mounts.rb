require 'libosctl'
require 'singleton'

module NodeCtld
  class ExportMounts
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

    # @param vps_ids [Array(Integer)]
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
      $CFG.get(:export_mounts, :enable)
    end

    def log_type
      'export-vpses'
    end

    protected

    ExportMount = Struct.new(:server_address, :server_path, :mountpoint, :nfs_version)

    def update_vps_worker
      loop do
        vps_id = @update_vps_queue.pop
        update_vps_keys(vps_id)
        sleep($CFG.get(:export_mounts, :update_vps_delay))
      end
    end

    def update_all_worker
      loop do
        @update_all_queue.pop(timeout: $CFG.get(:export_mounts, :update_all_interval))

        vps_ids = RpcClient.run(&:list_running_vps_ids)

        log(:info, "Updating export mounts of #{vps_ids.length} VPS")

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

      log(:info, "Updating export mounts of VPS #{vps_id}")
      t = Time.now

      begin
        mounts = read_vps_mounts(vps_id, domain)
      rescue StandardError => e
        log(
          :warn,
          "Unable to read mounts from VPS #{vps_id}: #{e.message} (#{e.class})"
        )
        return
      ensure
        conn.close
      end

      return if mounts.empty?

      NodeBunny.publish_wait(
        @exchange,
        {
          vps_id: vps_id,
          time: t.to_i,
          mounts: mounts.map do |mnt|
            {
              server_address: mnt.server_address,
              server_path: mnt.server_path,
              mountpoint: mnt.mountpoint,
              nfs_version: mnt.nfs_version
            }
          end
        }.to_json,
        content_type: 'application/json',
        routing_key: 'export_mounts'
      )
    end

    def read_vps_mounts(vps_id, domain)
      cfg = VpsConfig.read(vps_id)
      cmd = %w[cat /proc/1/mountinfo]

      begin
        st, out, err =
          if cfg.vm_type == 'qemu_container'
            vmctexec(domain, cmd)
          else
            vmexec(domain, cmd)
          end
      rescue Libvirt::Error => e
        log(:warn, "Error occurred while reading mountinfo from VPS #{vps_id}: #{e.message} (#{e.class})")
        return []
      end

      if st != 0 || out.nil?
        log(:warn, "Failed to read mountinfo from VPS #{vps_id}: #{err.inspect}")
        return []
      end

      mounts = []

      out.each_line do |line|
        mnt = parse_line(line)
        next if mnt.nil?

        mounts << mnt
      end

      mounts
    end

    def parse_line(line)
      fields = line.split

      dash = fields.index('-')
      return if dash.nil?

      fstype = fields[dash + 1]
      return if fstype.nil? || !%w[nfs nfs4].include?(fstype)

      mountpoint = fields[4]
      return if mountpoint.nil?

      server = fields[dash + 2]
      return if server.nil?

      server_address, server_path = server.split(':', 2)
      return if server_path.nil?

      options = fields[(dash + 3)..].join(',').split(',')

      vers = options.detect do |opt|
        opt.start_with?('vers=')
      end

      ExportMount.new(
        server_address,
        server_path,
        mountpoint,
        vers[5..]
      )
    end
  end
end
