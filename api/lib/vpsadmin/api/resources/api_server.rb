module VpsAdmin::API::Resources
  class ApiServer < HaveAPI::Resource
    desc 'Manage the API server itself'

    class UnlockTransactionSigningKey < HaveAPI::Action
      desc 'Unlock private key used for signing transactions'

      input(:hash) do
        string :passphrase, label: 'Passphrase', required: true
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def exec
        VpsAdmin::API::TransactionSigner.unlock(input[:passphrase])
        ok
      rescue VpsAdmin::API::TransactionSigner::Error => e
        error(e.message)
      end
    end
  end
end
