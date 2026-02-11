# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API' do
  describe 'GET /webauthn/registration/new' do
    let(:redirect_uri) { 'https://example.invalid/return' }

    it 'rejects unauthenticated access without redirect' do
      get '/webauthn/registration/new'

      expect(last_response.status).to eq(401)
      expect(last_response.body).to include('Access denied')
    end

    it 'redirects unauthenticated access when redirect_uri is provided' do
      get '/webauthn/registration/new', redirect_uri: redirect_uri

      expect(last_response.status).to eq(302)
      location = last_response.headers['Location']
      expect(location).to include(redirect_uri)
      expect(location).to include('registerStatus=0')
      expect(location).to include('registerMessage=Access+denied')
    end

    it 'returns HTML for authenticated users' do
      as(SpecSeed.user) do
        get '/webauthn/registration/new',
            access_token: 'spec-access-token',
            redirect_uri: redirect_uri
      end

      expect(last_response.status).to eq(200)
      expect(last_response.headers['Content-Type']).to include('text/html')
      expect(last_response.body).to include('vpsAdmin Passkey Registration')
      expect(last_response.body).to include('registerCredential')
      expect(last_response.body).to include('spec-access-token')
    end
  end
end
