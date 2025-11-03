require 'libosctl'
require 'singleton'

module NodeCtld
  class VpsOsRelease
    include Singleton
    include OsCtl::Lib::Utils::Log
    include Utils::Libvirt

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

    RELEASE_FILES = %w[
      /etc/os-release
      /usr/lib/os-release
    ].freeze

    class << self
      %i[update_domain update_vps_ids update_all_vps].each do |v|
        define_method(v) do |*args, **kwargs, &block|
          instance.send(v, *args, **kwargs, &block)
        end
      end
    end

    def initialize
      return unless enable?

      @channel = NodeBunny.create_channel
      @exchange = @channel.direct(NodeBunny.exchange_name)
    end

    # @param domain [Libvirt::Domain]
    def update_domain(domain)
      return if !enable? || !domain.active?

      log(:info, "Updating os-release of VPS #{domain.name}")

      # TODO: skip in rescue mode
      # if ct.in_ct_boot?
      #   log(:info, "VPS #{ct.id} is in rescue mode, skipping")
      #   return
      # end

      t = Time.now

      begin
        os_release = parse_os_release(domain)
      rescue StandardError => e
        log(
          :warn,
          "Unable to read os-release from VPS #{domain.name}}: #{e.message} (#{e.class})"
        )
        return
      end

      return if os_release.empty?

      NodeBunny.publish_wait(
        @exchange,
        {
          vps_id: domain.name.to_i,
          time: t.to_i,
          os_release:
        }.to_json,
        content_type: 'application/json',
        routing_key: 'vps_os_releases'
      )

      nil
    end

    # @param vps_ids [Array<Integer>]
    def update_vps_ids(vps_ids)
      return if !enable? || vps_ids.empty?

      conn = LibvirtClient.new

      conn.list_domains.each do |domain_id|
        domain = conn.lookup_domain_by_id(domain_id)
        next if !vps_ids.include?(domain.name.to_i) || !domain.active?

        update_domain(domain)
        sleep($CFG.get(:vps_os_release, :update_vps_delay))
      end

      conn.close

      nil
    end

    def update_all_vps
      return unless enable?

      vps_ids = []

      RpcClient.run do |rpc|
        rpc.list_running_vps_ids.each do |vps_id|
          vps_ids << vps_id
        end
      end

      log(:info, "Updating os-release of #{vps_ids.length} VPS")

      conn = LibvirtClient.new

      vps_ids.each do |vps_id|
        domain = conn.lookup_domain_by_name(vps_id.to_s)
        next if domain.nil? || !domain.active?

        update_domain(domain)
        sleep($CFG.get(:vps_os_release, :update_vps_delay))
      end

      conn.close

      nil
    end

    def enable?
      $CFG.get(:vps_os_release, :enable)
    end

    def log_type
      'vps-os-release'
    end

    protected

    # @param domain [Libvirt::Domain]
    # @return [Hash]
    def parse_os_release(domain)
      os_release = nil

      RELEASE_FILES.each do |release_file|
        os_release = parse_os_release_file(domain, release_file)
        break if os_release
      end

      if os_release.nil? || os_release.empty?
        log(:warn, "Unable to read os-release from VPS #{domain.name}")
      end

      os_release || {}
    end

    # @return [Hash, nil]
    def parse_os_release_file(domain, file)
      cfg = VpsConfig.read(domain.name.to_i)
      cmd = ['head', '-n100', file]

      begin
        st, out, =
          if cfg.vm_type == 'qemu_container'
            vmctexec(domain, cmd)
          else
            vmexec(domain, cmd)
          end
      rescue Libvirt::Error => e
        log(:warn, "Error occurred while reading os-release from VPS #{domain.name}: #{e.message} (#{e.class})")
        return
      end

      return if st != 0 || out.nil?

      parse_os_release_string(out)
    end

    # @param str [String]
    # @return [Hash]
    def parse_os_release_string(str)
      ret = {}
      max_lines = 100
      max_length = 256

      str.each_line do |line|
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
