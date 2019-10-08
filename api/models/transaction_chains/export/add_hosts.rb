module TransactionChains
  class Export::AddHosts < ::TransactionChain
    label 'Hosts+'

    # @param export [::Export]
    # @param hosts [Array<::ExportHost>]
    def link_chain(export, hosts)
      concerns(:affect, [export.class.name, export.id])

      ret = []
      ipv4_hosts = hosts.select { |h| h.ip_address.version == 4 }

      if ipv4_hosts.any?
        append_t(Transactions::Export::AddHosts, args: [export, ipv4_hosts]) do |t|
          ipv4_hosts.each do |host|
            host.save!
            ret << host
            t.just_create(host)
          end
        end
      end

      ret
    end
  end
end
