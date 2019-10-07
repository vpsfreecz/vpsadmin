module TransactionChains
  class Export::AddHosts < ::TransactionChain
    label 'Hosts+'

    # @param export [::Export]
    # @param ip_addresses [Array<::IpAddress>]
    def link_chain(export, ip_addresses)
      concerns(:affect, [export.class.name, export.id])

      ret = []
      ipv4s = ip_addresses.select { |ip| ip.version == 4 }

      if ipv4s.any?
        append_t(Transactions::Export::AddHosts, args: [export, ipv4s]) do |t|
          ipv4s.each do |ip|
            host = ::ExportHost.create!(export: export, ip_address: ip)
            ret << host
            t.just_create(host)
          end
        end
      end

      ret
    end
  end
end
