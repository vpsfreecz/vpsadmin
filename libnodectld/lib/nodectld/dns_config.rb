require 'singleton'
require 'libosctl'

module NodeCtld
  class DnsConfig
    include Singleton
    include OsCtl::Lib::Utils::File

    def initialize
      @config_root = $CFG.get(:dns_server, :config_root)
      @db_file = "#{@config_root}.json"
      @mutex = Mutex.new
      @zones =
        begin
          JSON.parse(File.read(@db_file), symbolize_names: true)['zones'].to_h do |name|
            [name, DnsServerZone.new(name)]
          end
        rescue Errno::ENOENT
          {}
        end
    end

    def add_zone(dns_server_zone)
      @mutex.synchronize do
        @zones[dns_server_zone.name] = dns_server_zone
        save
      end

      nil
    end

    def update_zone(dns_server_zone)
      @mutex.synchronize do
        @zones[dns_server_zone.name] = dns_server_zone
        save
      end

      nil
    end

    def remove_zone(dns_server_zone)
      @mutex.synchronize do
        @zones.delete(dns_server_zone.name)
        save
      end

      nil
    end

    def get_zone_names
      @mutex.synchronize { @zones.keys }
    end

    protected

    def save
      regenerate_file(@db_file, 0o644) do |f|
        f.puts(JSON.pretty_generate({ zones: @zones.keys }))
      end

      regenerate_file(@config_root, 0o644) do |f|
        @zones.each do |name, zone|
          if !zone.enabled
            f.puts(" # zone #{name} is disabled\n")
            next
          elsif zone.source == 'external_source' && zone.primaries.empty?
            f.puts(" # zone #{name} has no primaries")
            next
          end

          if zone.tsig_algorithm != 'none'
            f.puts("key \"#{name}-key\" {")
            f.puts("  algorithm #{zone.tsig_algorithm};")
            f.puts("  secret \"#{zone.tsig_key}\";")
            f.puts("};\n")
          end

          f.puts("zone \"#{name}\" {")

          if zone.source == 'internal_source'
            f.puts('  type primary;')
            f.puts("  allow-transfer { #{list_secondaries(zone, zone.secondaries)} };")
            f.puts('  notify yes;')
          else
            f.puts('  type secondary;')
            f.puts("  primaries { #{list_primaries(zone, zone.primaries)} };")
          end

          f.puts("  file \"#{zone.zone_file}\";")
          f.puts('  allow-query { any; };')
          f.puts("};\n")
        end
      end
    end

    def list_primaries(zone, hosts)
      hosts.map do |v|
        if zone.tsig_algorithm == 'none'
          "#{v};"
        else
          "#{v} key #{zone.name}-key;"
        end
      end.join(' ')
    end

    def list_secondaries(zone, hosts)
      ret = hosts.map { |v| "#{v};" }.join(' ')

      if zone.tsig_algorithm == 'none'
        ret
      else
        "key #{zone.name}-key; #{ret}"
      end
    end
  end
end
