require 'libosctl'
require 'singleton'

module NodeCtld
  class VpsOsRelease
    include Singleton
    include OsCtl::Lib::Utils::Log
    include OsCtl::Lib::Utils::System
    include Utils::OsCtl

    OPTIONS = %w[
      # General
      NAME
      ID
      ID_LIKE
      PRETTY_NAME
      CPE_NAME

      # OS version
      VARIANT
      VARIANT_ID
      VERSION
      VERSION_ID
      VERSION_CODENAME
      BUILD_ID
      IMAGE_ID
      IMAGE_VERSION
    ].freeze

    class << self
      %i[update_ct].each do |v|
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

    # @param ct [OsCtlContainer]
    def update_ct(ct)
      return unless enable?

      @update_vps_queue.insert(ct)
    end

    def enable?
      $CFG.get(:vps_os_release, :enable)
    end

    def log_type
      'vps-os-release'
    end

    protected

    def update_vps_worker
      loop do
        ct = @update_vps_queue.pop
        update_vps_os_release(ct)
        sleep($CFG.get(:vps_os_release, :update_vps_delay))
      end
    end

    def update_all_worker
      loop do
        sleep($CFG.get(:vps_os_release, :update_all_interval))

        vps_ids = {}

        RpcClient.run do |rpc|
          rpc.list_running_vps_ids.each do |vps_id|
            vps_ids[vps_id] = true
          end
        end

        log(:info, "Updating os-release of #{vps_ids.length} VPS")

        osctl_parse(%i[ct ls], vps_ids.keys, { state: 'running' }).each do |ct|
          next unless /^\d+$/ =~ ct[:id]

          osctl_ct = OsCtlContainer.new(ct)

          next unless vps_ids.has_key?(osctl_ct.vps_id)

          @update_vps_queue << osctl_ct
        end
      end
    end

    # @param ct [OsCtlContainer]
    def update_vps_os_release(ct)
      log(:info, "Updating os-release of VPS #{ct.id}")

      if ct.in_ct_boot?
        log(:info, "VPS #{ct.id} is in rescue mode, skipping")
        return
      end

      t = Time.now

      begin
        os_release = parse_os_release(ct)
      rescue StandardError => e
        log(
          :warn,
          "Unable to read os-release from VPS #{ct.id}: #{e.message} (#{e.class})"
        )
        return
      end

      return if os_release.empty?

      NodeBunny.publish_wait(
        @exchange,
        {
          vps_id: ct.vps_id,
          time: t.to_i,
          os_release:
        }.to_json,
        content_type: 'application/json',
        routing_key: 'vps_os_releases'
      )
    end

    # @param ct [OsCtlContainer]
    # @return [Hash]
    def parse_os_release(ct)
      read_r, read_w = IO.pipe

      # Chroot into VPS rootfs and read os-release files
      read_pid = Process.fork do
        read_r.close

        sys = OsCtl::Lib::Sys.new
        sys.chroot(ct.boot_rootfs)

        parsed = nil

        %w[/etc/os-release /usr/lib/os-release].each do |path|
          parsed = File.open(path) { |f| parse_os_release_io(f) }
        rescue Errno::ENOENT
          next
        end

        read_w.write((parsed || {}).to_json)
      end

      read_w.close

      begin
        os_release = JSON.parse(read_r.read)
      rescue JSON::ParserError
        log(:warn, "Failed to parse os-release for VPS #{ct.id}")
      end

      Process.wait(read_pid)
      log(:warn, "Reader for VPS #{ct.id} exited with #{$?.exitstatus}") if $?.exitstatus != 0

      os_release || {}
    end

    # @param io [IO]
    # @return [Hash]
    def parse_os_release_io(io)
      ret = {}
      max_lines = 100
      max_length = 256

      io.each_line do |line|
        stripped = line.strip
        next if stripped.empty? || stripped.start_with?('#')

        eq = stripped.index('=')
        next if eq.nil?

        key = stripped[0..(eq - 1)]
        next unless OPTIONS.include?(key)

        value = stripped[(eq + 1)..]
        value = value[1..-2] if value.start_with?('"') || value.start_with?('\'')
        next if value.length > max_length

        ret[key] = parse_value(key, value)

        max_lines -= 1
        break if max_lines < 0
      end

      ret
    end

    def parse_value(key, value)
      case key
      when 'ID_LIKE'
        value.split
      else
        value
      end
    end
  end
end
