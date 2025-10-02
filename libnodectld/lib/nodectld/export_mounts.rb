require 'libosctl'
require 'singleton'

module NodeCtld
  class ExportMounts
    include Singleton
    include OsCtl::Lib::Utils::Log
    include OsCtl::Lib::Utils::System
    include Utils::OsCtl

    class << self
      %i[update_ct update_vps_ids update_all_vps].each do |v|
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

    # @param ct [OsCtlContainer]
    def update_ct(ct)
      return unless enable?

      @update_vps_queue.insert(ct)
      nil
    end

    # @param vps_ids [Array(Integer)]
    def update_vps_ids(vps_ids)
      return if !enable? || vps_ids.empty?

      osctl_parse(%i[ct ls], vps_ids, { state: 'running' }).each do |ct|
        osctl_ct = OsCtlContainer.new(ct)

        # While ct ls returns only the selected containers, let's be sure
        next unless vps_ids.include?(osctl_ct.vps_id)

        @update_vps_queue << osctl_ct
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
        ct = @update_vps_queue.pop
        update_vps_keys(ct)
        sleep($CFG.get(:export_mounts, :update_vps_delay))
      end
    end

    def update_all_worker
      loop do
        @update_all_queue.pop(timeout: $CFG.get(:export_mounts, :update_all_interval))

        vps_ids = {}

        RpcClient.run do |rpc|
          rpc.list_running_vps_ids.each do |vps_id|
            vps_ids[vps_id] = true
          end
        end

        log(:info, "Updating export mounts of #{vps_ids.length} VPS")

        osctl_parse(%i[ct ls], vps_ids.keys, { state: 'running' }).each do |ct|
          next unless /^\d+$/ =~ ct[:id]

          osctl_ct = OsCtlContainer.new(ct)

          next unless vps_ids.has_key?(osctl_ct.vps_id)

          @update_vps_queue << osctl_ct
        end
      end
    end

    # @param ct [OsCtlContainer]
    def update_vps_keys(ct)
      log(:info, "Updating export mounts of VPS #{ct.id}")
      t = Time.now

      begin
        mounts = read_vps_mounts(ct)
      rescue StandardError => e
        log(
          :warn,
          "Unable to read mounts from VPS #{ct.id}: #{e.message} (#{e.class})"
        )
        return
      end

      return if mounts.empty?

      NodeBunny.publish_wait(
        @exchange,
        {
          vps_id: ct.vps_id,
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

    def read_vps_mounts(ct)
      return if ct.init_pid.nil?

      mounts = []

      File.open(File.join('/proc', ct.init_pid.to_s, 'mountinfo')) do |f|
        f.each_line do |line|
          mnt = parse_line(line)
          next if mnt.nil?

          mounts << mnt
        end
      end

      mounts
    end

    def parse_line(line)
      fields = line.split

      dash = fields.index('-')
      return if dash.nil?

      fstype = fields[dash + 1]
      return if fstype.nil? || fstype != 'nfs'

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
