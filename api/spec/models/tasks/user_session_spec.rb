# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Tasks::UserSession do
  around do |example|
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  let(:task) { described_class.new }
  let(:user) { SpecSeed.user }

  describe '#close_expired' do
    it 'destroys tokens and closes expired sessions without refreshable OAuth2 authorization' do
      session = create_detached_token_session!(user: user)
      expired_at = 1.hour.ago
      token_id = session.token_id
      session.token.update!(valid_to: expired_at)

      with_env('EXECUTE' => 'yes') { task.close_expired }

      expect(session.reload.token).to be_nil
      expect(session.closed_at.to_i).to eq(expired_at.to_i)
      expect(Token.find_by(id: token_id)).to be_nil
    end

    it 'keeps expired sessions open when a refreshable OAuth2 authorization exists' do
      fixture = create_auth_cleanup_fixture!(user: user)
      session = fixture.fetch(:token_session)
      token_id = session.token_id
      session.token.update!(valid_to: 1.hour.ago)

      with_env('EXECUTE' => 'yes') { task.close_expired }

      expect(session.reload.closed_at).to be_nil
      expect(session.token).to be_nil
      expect(Token.find_by(id: token_id)).to be_nil
      expect(fixture.fetch(:oauth2_authorization).reload.refresh_token).to be_present
    end

    it 'closes open OAuth2 authorizations when their refresh token expires' do
      fixture = create_auth_cleanup_fixture!(user: user)
      session = fixture.fetch(:token_session)
      authorization = fixture.fetch(:oauth2_authorization)
      refresh_expired_at = 1.hour.ago
      old_session_token = session.token
      session.update!(token: nil)
      old_session_token.destroy!
      authorization.refresh_token.update!(valid_to: refresh_expired_at)

      with_env('EXECUTE' => 'yes') { task.close_expired }

      expect(authorization.reload.refresh_token).to be_nil
      expect(session.reload.closed_at.to_i).to eq(refresh_expired_at.to_i)
    end

    it 'closes unusable SSO sessions and expired user devices' do
      fixture = create_auth_cleanup_fixture!(user: user)
      sso = fixture.fetch(:single_sign_on)
      device = fixture.fetch(:oauth2_authorization).user_device
      sso.token.update!(valid_to: 1.hour.ago)
      device.token.update!(valid_to: 1.hour.ago)

      with_env('EXECUTE' => 'yes') { task.close_expired }

      expect(sso.reload.token).to be_nil
      expect(device.reload.token).to be_nil
    end

    it 'does not persist changes in dry-run mode' do
      session = create_detached_token_session!(user: user)
      session.token.update!(valid_to: 1.hour.ago)

      task.close_expired

      expect(session.reload.token).to be_present
      expect(session.closed_at).to be_nil
    end
  end
end
