module TransactionChains
  class Export::AddHostsToAll < ::TransactionChain
    label 'Hosts+'

    # @param user [::User]
    # @param ip_addresses [Array<::IpAddress>]
    def link_chain(user, ip_addresses, reserved_ips: false)
      ::Export.where(user:, all_vps: true).each do |export|
        hosts = ip_addresses.map do |ip|
          ::ExportHost.new(
            export:,
            ip_address: ip,
            rw: export.rw,
            sync: export.sync,
            subtree_check: export.subtree_check,
            root_squash: export.root_squash
          )
        end

        use_chain(Export::AddHosts, args: [export, hosts], kwargs: { reserved_ips: })
      end
    end
  end
end
