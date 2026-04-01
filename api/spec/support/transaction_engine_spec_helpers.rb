# frozen_string_literal: true

require 'base64'
require 'openssl'

module TransactionEngineSpecHelpers
  def with_current_context(user: SpecSeed.admin)
    previous_user = ::User.current
    previous_session = ::UserSession.current

    ::User.current = user
    ::UserSession.current = ::UserSession.create!(
      user:,
      auth_type: 'basic',
      api_ip_addr: '127.0.0.1',
      client_version: 'RSpec'
    )

    yield(::UserSession.current)
  ensure
    ::User.current = previous_user
    ::UserSession.current = previous_session
  end

  def lock_transaction_signer!
    TransactionKeyHelpers.reset_transaction_signer!
  end

  def unlock_transaction_signer!
    TransactionKeyHelpers.install_encrypted_transaction_key!
    TransactionKeyHelpers.reset_transaction_signer!
    ::VpsAdmin::API::TransactionSigner.unlock(TransactionKeyHelpers::TEST_PASSPHRASE)
  end

  def signer_private_key
    ::VpsAdmin::API::TransactionSigner.instance.instance_variable_get(:@key)
  end

  def verify_signature_base64!(data, signature)
    digest = OpenSSL::Digest.new('SHA256')

    expect(
      signer_private_key.public_key.verify(digest, Base64.decode64(signature), data)
    ).to be(true)
  end
end

RSpec.configure do |config|
  config.include TransactionEngineSpecHelpers
end
