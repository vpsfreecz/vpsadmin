# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Authentication::TokenConfig do
  let(:config) { described_class.new(nil, nil) }
  let(:user) { SpecSeed.user }
  let(:request) { build_request(user_agent: 'RSpec/TokenConfig') }

  before do
    user.reload.update!(enable_token_auth: true)
  end

  it 'finds a user only for a valid open token session with token auth enabled' do
    session = create_open_session!(user:, auth_type: 'token')
    token = session.token.token

    expect(config.find_user_by_token(request, token)).to eq(user)
    expect(config.find_user_by_token(request, 'missing')).to be_nil

    session.close!
    expect(config.find_user_by_token(request, token)).to be_nil

    disabled = create_open_session!(user:, auth_type: 'token')
    user.update!(enable_token_auth: false)
    expect(config.find_user_by_token(request, disabled.token.token)).to be_nil
  end

  it 'renews renewable tokens through the provider action handler' do
    session = create_open_session!(
      user:,
      auth_type: 'token',
      token_lifetime: 'renewable_manual',
      token_interval: 3600,
      valid_to: 1.minute.from_now
    )
    old_valid_to = session.token.valid_to

    result = described_class.renew.handle.call(
      HaveAPI::Authentication::Token::ActionRequest.new(
        request:,
        user:,
        token: session.token.token
      ),
      HaveAPI::Authentication::Token::ActionResult.new
    )

    expect(result).to be_ok
    expect(result.valid_to).to be > old_valid_to
    expect(session.reload.token.valid_to).to eq(result.valid_to)
  end

  it 'revokes token sessions through the provider action handler' do
    session = create_open_session!(user:, auth_type: 'token')

    result = described_class.revoke.handle.call(
      HaveAPI::Authentication::Token::ActionRequest.new(
        request:,
        user:,
        token: session.token.token
      ),
      HaveAPI::Authentication::Token::ActionResult.new
    )

    expect(result).to be_ok
    expect(session.reload.closed_at).not_to be_nil
    expect(session.token).to be_nil
  end
end
