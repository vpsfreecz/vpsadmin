module TransactionChains
  class Vps::Boot < ::TransactionChain
    label 'Boot'

    # @param vps [::Vps]
    # @param template [::OsTemplate]
    # @param mount_root_dataset [String, nil] mountpoint or nil
    # @param start_timeout ['infinity', Integer]
    def link_chain(vps, template, mount_root_dataset: nil, start_timeout: 'infinity')
      lock(vps.dataset_in_pool)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      append(Transactions::Vps::Boot, args: [vps, template], kwargs: {
               mount_root_dataset:,
               start_timeout:
             })

      vps.user.user_public_keys.where(auto_add: true).each do |key|
        use_chain(Vps::DeployPublicKey, args: [vps, key], reversible: :keep_going)
      end
    end
  end
end
