module TransactionChains
  class User::Destroy < ::TransactionChain
    label 'Destroy user'

    def link_chain(user)
      # Destroy VPSes
      # Destroy datasets
      # Free IP addresses
      # Destroy snapshot downloads
      # Destroy environment configs
      # Destroy user resources

      # Destroy all VPSes
      user.vpses.unscoped.all.each do |vps|
        use_chain(Vps::Destroy, args: vps)
      end

      # Destroy all datasets
      user.datasets.where(expiration: nil).order('full_name DESC').each do |ds|
        ds.set_object_state(:deleted, chain: self, reason: 'Owner deleted.')
      end

      # Destroy snapshot downloads
      user.snapshot_downloads.each do |dl|
        use_chain(Dataset::RemoveDownload, args: dl)
      end

      # Destroy DNS zones
      user.dns_zones.each do |dns_zone|
        use_chain(DnsZone::DestroyUser, args: [dns_zone])
      end

      append(Transactions::Utils::NoOp, args: FIXME) do
        # Free all IP addresses
        ::IpAddress.where(user:).each do |ip|
          edit(ip, user_id: nil)
        end

        # Destroy environment configs
        user.environment_user_configs.each do |cfg|
          just_destroy(cfg)
        end

        # Destroy user resource packages
        user.user_cluster_resource_packages.each do |pkg|
          just_destroy(pkg)
        end

        # Destroy user resources
        user.user_cluster_resources.each do |r|
          just_destroy(r)
        end

        # Destroy the user himself
        just_destroy(user)
      end
    end
  end
end
