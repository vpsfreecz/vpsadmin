# frozen_string_literal: true

module UnlockSignerHelpers
  def ensure_signer_unlocked!
    TransactionKeyHelpers.install_encrypted_transaction_key!
    TransactionKeyHelpers.reset_transaction_signer!

    as(SpecSeed.admin) do
      post vpath('/api_servers/unlock_transaction_signing_key'),
           JSON.dump(api_server: { passphrase: TransactionKeyHelpers::TEST_PASSPHRASE }),
           'CONTENT_TYPE' => 'application/json'
    end

    expect(last_response.status).to eq(200)
    expect(json['status']).to be(true)
  end
end

RSpec.configure do |config|
  config.include UnlockSignerHelpers
end
