# frozen_string_literal: true

require 'uri'

RSpec.describe VpsAdmin::API::Authentication::OAuth2Config do
  let(:user) { SpecSeed.user }
  let(:client) { create_oauth2_client! }
  let(:params) do
    {
      client_id: client.client_id, response_type: 'code', redirect_uri: client.redirect_uri,
      scope: 'all', state: 'opaque-state', theme: 'auto', theme_return: '1'
    }
  end

  before do
    SpecSeed.set_password!(user, 'secret')
    user.update!(enable_oauth2_auth: true, enable_single_sign_on: true,
                 enable_multi_factor_auth: false, enable_new_login_notification: false,
                 password_reset: false, lockout: false)
  end

  before(:example, :theme_response_hook) do
    if Gem.loaded_specs.fetch('haveapi').version.to_s == '0.32.2' &&
       Bundler.locked_gems.specs.find { |spec| spec.name == 'haveapi' }.source.is_a?(Bundler::Source::Rubygems) &&
       !HaveAPI::Authentication::OAuth2::Config.method_defined?(:authorization_response_params)
      pending 'Released HaveAPI 0.32.2 lacks the theme response hook; a future release is required'
    end
  end

  def callback_query
    URI.decode_www_form(URI.parse(last_response.headers.fetch('Location')).query).to_h
  end

  def password_login(values)
    post '/_auth/oauth2/authorize', values.merge(login_credentials: '1', user: user.login, password: 'secret')
  end

  it 'uses the real framework success hook without changing state, code or redirect authority', :theme_response_hook do
    password_login(params)
    expect(last_response.status).to eq(302)
    expect(callback_query).to include('theme' => 'auto', 'state' => 'opaque-state')
    expect(callback_query['code']).to be_present
    expect(URI.parse(last_response.headers['Location']).host).to eq(URI.parse(client.redirect_uri).host)
  end

  it 'uses the same hook when SSO succeeds without rendering a page', :theme_response_hook do
    sso = create_single_sign_on!(user:)
    device = create_user_device!(user:)
    set_cookie("vpsadmin_sso=#{sso.token.token}")
    set_cookie("vpsadmin_devices=#{device.token.token}")
    get '/_auth/oauth2/authorize', params.merge(theme: 'dark')
    expect(last_response.status).to eq(302)
    expect(callback_query).to include('theme' => 'dark', 'state' => 'opaque-state')
  end

  it 'does not extend a legacy client callback after an explicit provider theme choice' do
    password_login(params.except(:theme_return).merge(theme: 'light'))
    expect(last_response.status).to eq(302)
    expect(callback_query).not_to have_key('theme')
    expect(callback_query).to include('state' => 'opaque-state')
  end

  it 'ignores malformed appearance input without changing successful authentication' do
    password_login(params.merge(theme: ['dark']))
    expect(last_response.status).to eq(302)
    expect(callback_query).not_to have_key('theme')
  end

  it 'keeps cancellation payloads unchanged even for an opted-in client' do
    post '/_auth/oauth2/authorize', params.merge(cancel: 'Cancel')
    expect(last_response.status).to eq(302)
    expect(callback_query).to include('error' => 'access_denied', 'state' => 'opaque-state')
    expect(callback_query).not_to have_key('theme')
  end
end
