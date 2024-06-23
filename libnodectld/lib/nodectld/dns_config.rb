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
          JSON.parse(File.read(@db_file))['zones']
        rescue Errno::ENOENT
          {}
        end
    end

    def add_zone(dns_zone)
      @mutex.synchronize do
        @zones[dns_zone.name] = dns_zone.zone_file
        save
      end

      nil
    end

    def remove_zone(dns_zone)
      @mutex.synchronize do
        @zones.delete(dns_zone.name)
        save
      end

      nil
    end

    protected

    def save
      regenerate_file(@db_file, 0o644) do |f|
        f.puts(JSON.pretty_generate({ zones: @zones }))
      end

      regenerate_file(@config_root, 0o644) do |f|
        @zones.each do |name, file|
          f.puts("zone \"#{name}\" {")
          f.puts('  type master;')
          f.puts("  file \"#{file}\";")
          f.puts('  allow-query { any; };')
          f.puts("};\n")
        end
      end
    end
  end
end
