module TransactionChains
  class Vps::Boot < ::TransactionChain
    label 'Boot'

    # @param vps [::Vps]
    # @param template [::OsTemplate]
    # @param opts [Hash]
    # @option opts [String, nil] :mount_root_dataset mountpoint or nil
    def link_chain(vps, template, opts = {})
      lock(vps.dataset_in_pool)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      append(Transactions::Vps::Boot, args: [
        vps,
        template,
        {mount_root_dataset: opts[:mount_root_dataset]},
      ])

      vps.user.user_public_keys.where(auto_add: true).each do |key|
        use_chain(Vps::DeployPublicKey, args: [vps, key], reversible: :keep_going)
      end
    end
  end
end
