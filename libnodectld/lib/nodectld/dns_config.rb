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
          JSON.parse(File.read(@db_file))['zones'].to_h do |name, zone|
            [name, DnsServerZone.new(name:, source: zone['source'], type: zone['type'])]
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

    def any_zones?
      @mutex.synchronize { @zones.any? }
    end

    def [](name)
      @mutex.synchronize { @zones[name] }
    end

    protected

    def save
      regenerate_file(@db_file, 0o644) do |f|
        save_zones = @zones.transform_values do |zone|
          { source: zone.source, type: zone.type }
        end

        f.puts(JSON.pretty_generate({ zones: save_zones }))
      end

      regenerate_file(@config_root, 0o644) do |f|
        # First, find all TSIG keys
        tsig_keys = {}

        @zones.each_value do |zone|
          (zone.primaries + zone.secondaries).each do |s|
            k = s['tsig_key']
            next if k.nil?

            tsig_keys[k['name']] = k
          end
        end

        # Declare TSIG keys
        tsig_keys.each_value do |k|
          f.puts("key \"#{k['name']}\" {")
          f.puts("  algorithm #{k['algorithm']};")
          f.puts("  secret \"#{k['secret']}\";")
          f.puts("};\n")
        end

        # Declare zones
        @zones.each do |name, zone|
          if !zone.enabled
            f.puts(" # zone #{name} is disabled\n")
            next
          elsif (zone.source == 'external_source' || zone.type == 'secondary_type') && zone.primaries.empty?
            f.puts(" # zone #{name} has no primaries")
            next
          end

          f.puts("zone \"#{name}\" {")

          if zone.source == 'internal_source' && zone.type == 'primary_type'
            f.puts('  type primary;')
            f.puts("  allow-transfer { #{allow_transfer(zone.secondaries)} };")
            f.puts('  notify yes;')

            # We need this in case the nameserver mentioned in the SOA record
            # is actually a secondary server.
            f.puts('  notify-to-soa yes;')

            if zone.dnssec_enabled
              f.puts('  dnssec-policy default;')
              f.puts('  inline-signing yes;')
            end
          else
            f.puts('  type secondary;')
            f.puts("  primaries { #{list_primaries(zone.primaries)} };")

            if zone.secondaries.any?
              f.puts("  allow-transfer { #{allow_transfer(zone.secondaries)} };")
              f.puts('  notify yes;')
            else
              f.puts('  allow-transfer { none; };')
            end
          end

          f.puts("  file \"#{zone.zone_file}\";")
          f.puts('  allow-query { any; };')
          f.puts("};\n")
        end
      end
    end

    def allow_transfer(servers)
      servers.map do |s|
        if s['tsig_key']
          "key #{s['tsig_key']['name']};"
        else
          "#{s['ip_addr']};"
        end
      end.join(' ')
    end

    def list_primaries(servers)
      servers.map do |s|
        if s['tsig_key']
          "#{s['ip_addr']} key #{s['tsig_key']['name']};"
        else
          "#{s['ip_addr']};"
        end
      end.join(' ')
    end
  end
end
