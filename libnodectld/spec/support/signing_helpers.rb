# frozen_string_literal: true

module NodeCtldSpec
  module SigningHelpers
    class << self
      attr_reader :private_key, :public_key_path

      def install_suite_keypair!
        return if @private_key

        dir = Dir.mktmpdir('libnodectld-spec-keys')
        rsa = OpenSSL::PKey::RSA.new(2048)
        path = File.join(dir, 'transaction-public.pem')

        File.write(path, rsa.public_key.to_pem)

        @private_key = rsa
        @public_key_path = path
      end

      def sign_base64(data)
        digest = OpenSSL::Digest.new('SHA256')
        Base64.strict_encode64(@private_key.sign(digest, data))
      end

      def signed_input(chain_id:, depends_on_id:, handle:, node_id:, reversible:, input: {})
        payload = {
          transaction_chain: chain_id,
          depends_on: depends_on_id,
          handle: handle,
          node: node_id,
          reversible: reversible,
          input: input
        }.to_json

        [payload, sign_base64(payload)]
      end
    end
  end
end
