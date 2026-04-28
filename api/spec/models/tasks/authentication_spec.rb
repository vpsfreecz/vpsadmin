# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Tasks::Authentication do
  around do |example|
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  let(:task) { described_class.new }
  let(:user) { SpecSeed.user }
  let(:user_agent) { UserAgent.find_or_create!('RSpec auth task') }

  def create_auth_token!(valid_to: 1.hour.ago)
    token = Token.get!(valid_to: valid_to)
    AuthToken.create!(
      user: user,
      user_agent: user_agent,
      token: token,
      purpose: :mfa,
      api_ip_addr: '127.0.0.1',
      api_ip_ptr: 'localhost',
      client_ip_addr: '127.0.0.1',
      client_ip_ptr: 'localhost',
      client_version: 'RSpec'
    )
  end

  def create_webauthn_challenge!(type:, valid_to: 1.hour.ago)
    WebauthnChallenge.create!(
      user: user,
      user_agent: user_agent,
      token: Token.get!(valid_to: valid_to),
      challenge_type: type,
      challenge: SecureRandom.hex(32),
      api_ip_addr: '127.0.0.1',
      api_ip_ptr: 'localhost',
      client_ip_addr: '127.0.0.1',
      client_ip_ptr: 'localhost',
      client_version: 'RSpec'
    )
  end

  def create_oauth_client!
    Oauth2Client.new(
      name: "Spec OAuth #{SecureRandom.hex(4)}",
      client_id: "spec-#{SecureRandom.hex(8)}",
      redirect_uri: 'https://example.test/callback'
    ).tap do |client|
      client.set_secret('secret')
      client.save!
    end
  end

  def create_oauth_authorization!(code_valid_to: 1.hour.ago)
    Oauth2Authorization.create!(
      oauth2_client: create_oauth_client!,
      user: user,
      code: Token.get!(valid_to: code_valid_to),
      scope: ['*'],
      client_ip_addr: '127.0.0.1',
      user_agent: user_agent
    )
  end

  def create_failed_login_row!(login_user: user, auth_type: 'basic', reason: 'invalid password',
                               client_ip_addr: '127.0.0.1', agent: user_agent,
                               reported_at: nil)
    UserFailedLogin.create!(
      user: login_user,
      user_agent: agent,
      auth_type: auth_type,
      api_ip_addr: '127.0.0.1',
      api_ip_ptr: 'localhost',
      client_ip_addr: client_ip_addr,
      client_ip_ptr: 'localhost',
      client_version: 'RSpec',
      reason: reason,
      reported_at: reported_at
    )
  end

  describe '#close_expired' do
    it 'keeps expired authentication tokens in dry-run mode' do
      auth_token = create_auth_token!
      allow(VpsAdmin::API::Operations::User::IncompleteLogin).to receive(:run)

      task.close_expired

      expect(AuthToken.find_by(id: auth_token.id)).to be_present
      expect(VpsAdmin::API::Operations::User::IncompleteLogin).not_to have_received(:run)
    end

    it 'destroys expired authentication tokens and records incomplete login attempts in execute mode' do
      auth_token = create_auth_token!
      allow(VpsAdmin::API::Operations::User::IncompleteLogin).to receive(:run).and_call_original

      with_env('EXECUTE' => 'yes') { task.close_expired }

      expect(AuthToken.find_by(id: auth_token.id)).to be_nil
      expect(VpsAdmin::API::Operations::User::IncompleteLogin).to have_received(:run).with(
        auth_token,
        :totp,
        'authentication token expired'
      )
      expect(UserFailedLogin.where(user: user, auth_type: 'totp').count).to eq(1)
    end

    it 'destroys expired OAuth2 authorization codes without a user session' do
      authorization = create_oauth_authorization!

      with_env('EXECUTE' => 'yes') { task.close_expired }

      expect(Oauth2Authorization.find_by(id: authorization.id)).to be_nil
    end

    it 'records incomplete login for expired WebAuthn authentication challenges' do
      challenge = create_webauthn_challenge!(type: :authentication)
      allow(VpsAdmin::API::Operations::User::IncompleteLogin).to receive(:run).and_call_original

      with_env('EXECUTE' => 'yes') { task.close_expired }

      expect(WebauthnChallenge.find_by(id: challenge.id)).to be_nil
      expect(VpsAdmin::API::Operations::User::IncompleteLogin).to have_received(:run).with(
        challenge,
        :webauthn,
        'authentication challenge expired'
      )
      expect(UserFailedLogin.where(user: user, auth_type: 'webauthn').count).to eq(1)
    end

    it 'destroys non-authentication WebAuthn challenges without incomplete-login side effects' do
      challenge = create_webauthn_challenge!(type: :registration)
      allow(VpsAdmin::API::Operations::User::IncompleteLogin).to receive(:run)

      with_env('EXECUTE' => 'yes') { task.close_expired }

      expect(WebauthnChallenge.find_by(id: challenge.id)).to be_nil
      expect(VpsAdmin::API::Operations::User::IncompleteLogin).not_to have_received(:run)
    end
  end

  describe '#report_failed_logins' do
    it 'prints grouped counts in dry-run mode without firing the chain' do
      create_failed_login_row!
      create_failed_login_row!
      allow(TransactionChains::User::ReportFailedLogins).to receive(:fire2)

      expect { task.report_failed_logins }.to output(/User #{user.id}: 2 failed attempts/).to_stdout

      expect(TransactionChains::User::ReportFailedLogins).not_to have_received(:fire2)
    end

    it 'groups unreported attempts by user and attempt attributes in execute mode' do
      other_user = SpecSeed.other_user
      other_agent = UserAgent.find_or_create!('RSpec auth task other')
      grouped = [
        create_failed_login_row!(auth_type: 'basic', reason: 'invalid password', client_ip_addr: '127.0.0.1'),
        create_failed_login_row!(auth_type: 'basic', reason: 'invalid password', client_ip_addr: '127.0.0.1'),
        create_failed_login_row!(auth_type: 'token', reason: 'revoked token', client_ip_addr: '127.0.0.2'),
        create_failed_login_row!(login_user: other_user, auth_type: 'basic', agent: other_agent)
      ]
      create_failed_login_row!(reported_at: 1.hour.ago)
      captured = nil
      allow(TransactionChains::User::ReportFailedLogins).to receive(:fire2) do |args:|
        captured = args.fetch(0)
      end

      with_env('EXECUTE' => 'yes') { task.report_failed_logins }

      expect(TransactionChains::User::ReportFailedLogins).to have_received(:fire2).once
      expect(captured.keys).to contain_exactly(user, other_user)
      expect(captured.fetch(user).map { |grp| grp.map(&:id) }).to contain_exactly(
        grouped[0..1].map(&:id),
        [grouped[2].id]
      )
      expect(captured.fetch(other_user).map { |grp| grp.map(&:id) }).to eq([[grouped[3].id]])
    end
  end
end
