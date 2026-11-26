# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Authentication::WebauthnRegister do
  let(:user) { SpecSeed.user }

  before do
    allow(VpsAdmin::API::DeploymentConfig).to receive(:dig).with('authentication', 'light_logo_file')
                                                           .and_return(File.expand_path('../../../../../lib/vpsadmin/api/authentication/assets/vpsadmin.svg', __dir__))
  end

  it 'returns an HTML body with token header, redirect URI, and logo URL' do
    status, headers, body = described_class.run(
      user,
      {
        'redirect_uri' => 'https://app.example.test/passkey'
      },
      access_token: 'access-token-123'
    )

    expect(status).to eq(200)
    expect(headers['content-type']).to eq('text/html')
    expect(body).to include("'X-HaveAPI-OAuth2-Token': \"access-token-123\"")
    expect(body).not_to include('access_token=access-token-123')
    expect(body).not_to include('/webauthn/registration/begin?')
    expect(body).not_to include('/webauthn/registration/finish?')
    expect(body).to include('https://app.example.test/passkey')
    expect(body).to include('/_auth/appearance/logo/light')
    expect(body).not_to include('/_auth/appearance/logo/dark')
  end
end
