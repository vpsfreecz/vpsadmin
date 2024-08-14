module NodeCtld
  class Commands::DnsServerZone::Destroy < Commands::Base
    handle 5502
    needs :dns

    def exec
      zone = get_dns_server_zone
      zone.destroy
      DnsConfig.instance.remove_zone(zone)
      remove_dnssec_keys(zone) if zone.type == 'primary_type'
      ok
    end

    def rollback
      zone = get_dns_server_zone
      zone.replace_all_records(@records)
      DnsConfig.instance.add_zone(zone)
      restore_dnssec_keys(zone) if zone.type == 'primary_type'
      ok
    end

    protected

    def remove_dnssec_keys(zone)
      workdir = $CFG.get(:dns_server, :bind_workdir)

      Dir.entries(workdir).each do |v|
        next if /\AK#{Regexp.escape(zone.name)}\+\d+\+\d+\.(?:key|state|private)\z/ !~ v

        path = File.join(workdir, v)
        File.rename(path, "#{path}.destroyed-#{@command.id}")
      end
    end

    def restore_dnssec_keys(zone)
      workdir = $CFG.get(:dns_server, :bind_workdir)

      Dir.entries(workdir).each do |v|
        next if /\A(K#{Regexp.escape(zone.name)}\+\d+\+\d+\.(?:key|state|private))\.destroyed-#{@command.id}\z/ !~ v

        orig_name = Regexp.last_match(1)

        File.rename(File.join(workdir, v), File.join(workdir, orig_name))
      end
    end
  end
end
