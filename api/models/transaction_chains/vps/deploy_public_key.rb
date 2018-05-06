module TransactionChains::Vps
  class DeployPublicKey < ::TransactionChain
    label 'Pubkey'

    def link_chain(vps, key)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      append_t(Transactions::Vps::DeployPublicKey, args: [vps, key]) do |t|
        t.just_create(vps.log(:deploy_public_key, {
          id: key.id,
          label: key.label,
          key: key.key,
        }))
      end
    end
  end
end
