module TransactionChains
  class Export::DelHosts < ::TransactionChain
    label 'Hosts-'

    # @param export [::Export]
    # @param hosts_or_ip_addresses [Array<::ExportHost, ::IpAddress>]
    def link_chain(export, hosts_or_ip_addresses)
      concerns(:affect, [export.class.name, export.id])

      hosts = hosts_or_ip_addresses.map do |host_or_ip|
        if host_or_ip.is_a?(::ExportHost)
          host_or_ip
        else
          export.export_hosts.where(ip_address: host_or_ip).take
        end
      end.compact

      if hosts.any?
        append_t(
          Transactions::Export::DelHosts,
          args: [export, hosts],
        ) do |t|
          hosts.each do |host|
            t.just_destroy(host)
          end
        end
      end
    end
  end
end
