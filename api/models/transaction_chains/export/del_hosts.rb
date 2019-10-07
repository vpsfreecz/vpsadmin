module TransactionChains
  class Export::DelHosts < ::TransactionChain
    label 'Hosts-'

    # @param export [::Export]
    # @param ip_addresses [Array<::IpAddress>]
    def link_chain(export, ip_addresses)
      concerns(:affect, [export.class.name, export.id])

      hosts = ip_addresses.map do |ip|
        export.export_hosts.where(ip_address: ip).take
      end.compact

      if hosts.any?
        append_t(
          Transactions::Export::DelHosts,
          args: [export, hosts.map(&:ip_address)],
        ) do |t|
          hosts.each do |host|
            t.just_destroy(host)
          end
        end
      end
    end
  end
end
