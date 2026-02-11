# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API::Resources::ApiServer' do
  before do
    header 'Accept', 'application/json'
    TransactionKeyHelpers.install_encrypted_transaction_key!
    TransactionKeyHelpers.reset_transaction_signer!
  end

  def unlock_path
    vpath('/api_servers/unlock_transaction_signing_key')
  end

  def json_post(path, payload)
    post path, JSON.dump(payload), {
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def response_errors
    json.dig('response', 'errors') || json['errors'] || {}
  end

  def response_message
    json['message'] || json.dig('response', 'message')
  end

  def expect_status(code)
    path = last_request&.path
    message = "Expected status #{code} for #{path}, got #{last_response.status} body=#{last_response.body}"
    expect(last_response.status).to eq(code), message
  end

  describe 'UnlockTransactionSigningKey' do
    let(:payload) do
      { api_server: { passphrase: TransactionKeyHelpers::TEST_PASSPHRASE } }
    end

    it 'rejects unauthenticated access' do
      json_post unlock_path, payload

      expect_status(401)
      expect(json['status']).to be(false)
    end

    it 'forbids normal users' do
      as(SpecSeed.user) { json_post unlock_path, payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'forbids support users' do
      as(SpecSeed.support) { json_post unlock_path, payload }

      expect_status(403)
      expect(json['status']).to be(false)
    end

    it 'allows admin to unlock with correct passphrase' do
      as(SpecSeed.admin) { json_post unlock_path, payload }

      expect_status(200)
      expect(json['status']).to be(true)
      expect(TransactionKeyHelpers.signer_locked?).to be(false)
    end

    it 'rejects wrong passphrase' do
      as(SpecSeed.admin) do
        json_post unlock_path, api_server: { passphrase: 'wrong-passphrase' }
      end

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message.to_s.downcase).to include('passphrase')
      expect(TransactionKeyHelpers.signer_locked?).to be(true)
    end

    it 'returns validation errors for missing passphrase' do
      as(SpecSeed.admin) { json_post unlock_path, api_server: {} }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_errors).to be_a(Hash)
      expect(response_errors.keys.map(&:to_s)).to include('passphrase')
      expect(TransactionKeyHelpers.signer_locked?).to be(true)
    end

    it 'errors when transaction key is not configured' do
      SysConfig.find_by!(category: 'core', name: 'transaction_key').update!(value: nil)
      TransactionKeyHelpers.reset_transaction_signer!

      as(SpecSeed.admin) { json_post unlock_path, payload }

      expect_status(200)
      expect(json['status']).to be(false)
      expect(response_message.to_s.downcase).to include('transaction')
      expect(TransactionKeyHelpers.signer_locked?).to be(true)
    end
  end
end
