module TransactionChains
  class Export::AddHostsToAll < ::TransactionChain
    label 'Hosts+'

    # @param user [::User]
    # @param ip_addresses [Array<::IpAddress>]
    def link_chain(user, ip_addresses)
      ::Export.where(user: user, all_vps: true).each do |export|
        hosts = ip_addresses.map do |ip|
          ::ExportHost.new(
            export: export,
            ip_address: ip,
            rw: export.rw,
            sync: export.sync,
            subtree_check: export.subtree_check,
            root_squash: export.root_squash,
          )
        end

        use_chain(Export::AddHosts, args: [export, hosts])
      end
    end
  end
end
