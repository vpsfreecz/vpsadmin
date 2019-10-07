module TransactionChains
  class Export::DelHostsFromAll < ::TransactionChain
    label 'Hosts-'

    # @param user [::User]
    # @param ip_addresses [Array<::IpAddress>]
    def link_chain(user, ip_addresses)
      ::Export.where(user: user).each do |export|
        use_chain(Export::DelHosts, args: [export, ip_addresses])
      end
    end
  end
end
