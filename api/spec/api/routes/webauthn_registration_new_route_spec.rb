# frozen_string_literal: true

RSpec.describe 'VpsAdmin::API' do
  describe '/webauthn/registration/new' do
    let(:redirect_uri) { 'https://example.invalid/return' }
    let(:user) { SpecSeed.user }
    let(:session) { create_open_session!(user:, auth_type: 'oauth2') }

    it 'rejects unauthenticated access without redirect' do
      get '/webauthn/registration/new'

      expect(last_response.status).to eq(401)
      expect(last_response.body).to include('Access denied')
    end

    it 'localizes unauthenticated access without redirect' do
      header 'Accept-Language', 'cs'

      get '/webauthn/registration/new'

      expect(last_response.status).to eq(401)
      expect(last_response.body).to include('Přístup odepřen')
    end

    it 'redirects unauthenticated access when redirect_uri is provided' do
      get '/webauthn/registration/new', redirect_uri: redirect_uri

      expect(last_response.status).to eq(302)
      location = last_response.headers['Location']
      expect(location).to include(redirect_uri)
      expect(location).to include('registerStatus=0')
      expect(location).to include('registerMessage=Access+denied')
    end

    it 'localizes unauthenticated redirect message' do
      header 'Accept-Language', 'cs'

      get '/webauthn/registration/new', redirect_uri: redirect_uri

      expect(last_response.status).to eq(302)
      location = last_response.headers['Location']
      expect(location).to include('registerStatus=0')
      expect(URI.decode_www_form(URI(location).query).to_h['registerMessage'])
        .to eq('Přístup odepřen, kontaktujte prosím podporu.')
    end

    it 'rejects access tokens sent in URLs' do
      get '/webauthn/registration/new',
          access_token: session.token.token,
          redirect_uri: redirect_uri

      expect(last_response.status).to eq(400)
      expect(last_response.body).to include('must not be sent in URL')
    end

    it 'returns HTML for users authenticated by POST body' do
      post '/webauthn/registration/new',
           access_token: session.token.token,
           redirect_uri: redirect_uri

      expect(last_response.status).to eq(200)
      expect(last_response.headers['Content-Type']).to include('text/html')
      expect(last_response.body).to include('vpsAdmin Passkey Registration')
      expect(last_response.body).to include('registerCredential')
      expect(last_response.body).to include('X-HaveAPI-OAuth2-Token')
      expect(last_response.body).to include(session.token.token)
      expect(last_response.body).not_to include('access_token=')
      expect(last_response.body).not_to include('/webauthn/registration/begin?')
      expect(last_response.body).not_to include('/webauthn/registration/finish?')
    end
  end
end
