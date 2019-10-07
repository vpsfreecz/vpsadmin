module TransactionChains
  class Export::AddHostsToAll < ::TransactionChain
    label 'Hosts+'

    # @param user [::User]
    # @param ip_addresses [Array<::IpAddress>]
    def link_chain(user, ip_addresses)
      ::Export.where(user: user, all_vps: true).each do |export|
        use_chain(Export::AddHosts, args: [export, ip_addresses])
      end
    end
  end
end
