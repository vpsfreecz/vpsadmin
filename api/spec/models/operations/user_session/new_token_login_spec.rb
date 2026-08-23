# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::UserSession::NewTokenLogin do
  let(:op) { described_class.new }
  let(:user) { SpecSeed.user }
  let(:request) { build_request(ip: '198.51.100.62', user_agent: 'RSpec/TokenLogin') }

  before do
    user.reload.update!(
      lockout: false,
      password_reset: false,
      enable_new_login_notification: false
    )
    stub_ptr_lookup!(op, ptr: 'ptr.example.test')
  end

  it 'performs User::Login, opens a token session, and sets current session' do
    allow(VpsAdmin::API::Operations::User::Login).to receive(:run).and_call_original
    allow(TransactionChains::User::NewToken).to receive(:fire2)

    session = op.run(
      user,
      request,
      'fixed',
      3600,
      ['all'],
      authentication_generation: user.authentication_generation
    )

    expect(VpsAdmin::API::Operations::User::Login).to have_received(:run).with(user, request)
    expect(TransactionChains::User::NewToken).not_to have_received(:fire2)
    expect(session).to be_persisted
    expect(session.auth_type).to eq('token')
    expect(session.token).to be_present
    expect(session.scope).to eq(['all'])
    expect(UserSession.current).to eq(session)
  end

  it 'fires NewToken only when notifications are enabled' do
    user.update!(enable_new_login_notification: true)

    allow(TransactionChains::User::NewToken).to receive(:fire2)

    op.run(
      user,
      request,
      'fixed',
      3600,
      ['all'],
      authentication_generation: user.authentication_generation
    )

    expect(TransactionChains::User::NewToken).to have_received(:fire2).with(args: [kind_of(UserSession)])
  end

  it 'atomically attaches a required password change to the new session' do
    password_change = PasswordChangeLog.create!(
      user:,
      source: 'forced_reset',
      created_at: Time.current
    )

    session = op.run(
      user,
      request,
      'fixed',
      3600,
      ['all'],
      authentication_generation: user.authentication_generation,
      password_change_log: password_change
    )

    expect(password_change.reload.user_session).to eq(session)
  end

  it 'rolls back session creation when the password change cannot be attached' do
    session_ids_before = UserSession.where(user:, auth_type: 'token').pluck(:id)
    password_change = PasswordChangeLog.create!(
      user: SpecSeed.other_user,
      source: 'forced_reset',
      created_at: Time.current
    )

    expect do
      op.run(
        user,
        request,
        'fixed',
        3600,
        ['all'],
        authentication_generation: user.authentication_generation,
        password_change_log: password_change
      )
    end.to raise_error(ArgumentError, 'user session belongs to another user')

    expect(UserSession.where(user:, auth_type: 'token').pluck(:id)).to eq(session_ids_before)
    expect(password_change.reload.user_session_id).to be_nil
  end

  it 'rejects session creation from an older authentication generation' do
    generation = user.authentication_generation
    user.set_password('new-secret')
    user.save!

    expect do
      op.run(
        user,
        request,
        'fixed',
        3600,
        ['all'],
        authentication_generation: generation
      )
    end.to raise_error(VpsAdmin::API::Exceptions::OperationError, 'authentication expired')

    expect(UserSession.where(user:, auth_type: 'token')).to be_empty
  end
end
