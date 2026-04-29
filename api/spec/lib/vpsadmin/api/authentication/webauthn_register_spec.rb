# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Authentication::WebauthnRegister do
  let(:user) { SpecSeed.user }

  before do
    SysConfig.find_or_create_by!(category: 'core', name: 'logo_url').update!(
      value: 'https://assets.example.test/logo.png'
    )
  end

  it 'returns an HTML body with token, redirect URI, and logo URL' do
    status, headers, body = described_class.run(
      user,
      {
        'access_token' => 'access-token-123',
        'redirect_uri' => 'https://app.example.test/passkey'
      }
    )

    expect(status).to eq(200)
    expect(headers['content-type']).to eq('text/html')
    expect(body).to include('access_token=access-token-123')
    expect(body).to include('https://app.example.test/passkey')
    expect(body).to include('https://assets.example.test/logo.png')
  end
end
