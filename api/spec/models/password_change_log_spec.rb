# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PasswordChangeLog do
  def create_session(user)
    UserSession.create!(
      user:,
      auth_type: 'basic',
      api_ip_addr: '192.0.2.100',
      client_ip_addr: '192.0.2.100',
      user_agent: UserAgent.find_or_create!('Password change log spec'),
      client_version: 'Password change log spec',
      scope: ['all'],
      label: 'Password change session',
      token_lifetime: :fixed,
      token_interval: 3600
    )
  end

  it 'records the selected source and exact initiating session' do
    user = create_lifecycle_user!
    session = create_session(user)

    user.set_password(
      'new-password',
      source: :authenticated,
      user_session: session
    )
    user.save!

    change = described_class.find_by!(user:)
    expect(change).to have_attributes(
      user_session_id: session.id,
      source: 'authenticated'
    )
    expect(change.created_at).to be_present
    expect(change.user_session_owned_by_user).to be(true)
    expect(
      PasswordEventCounter.find_by!(name: 'password_change_authenticated').event_count
    ).to eq(1)
  end

  it 'records sessionless password changes without creating a session' do
    user = create_lifecycle_user!

    user.set_password('new-password', source: :recovery, user_session: nil)
    user.save!

    expect(described_class.find_by!(user:)).to have_attributes(
      user_session_id: nil,
      source: 'recovery'
    )
    expect(described_class.find_by!(user:).user_session_owned_by_user).to be(false)
  end

  it 'distinguishes a session owned by another user' do
    user = create_lifecycle_user!
    administrator = create_lifecycle_user!
    session = create_session(administrator)

    change = described_class.create!(
      user:,
      user_session: session,
      source: 'administrator',
      created_at: Time.current
    )

    expect(change.user_session_owned_by_user).to be(false)
  end

  it 'does not record account creation or a rolled-back password update' do
    expect do
      create_lifecycle_user!
    end.not_to change(described_class, :count)

    user = create_lifecycle_user!
    session = create_session(user)
    old_password = user.password

    User.transaction(requires_new: true) do
      user.set_password(
        'rolled-back-password',
        source: :authenticated,
        user_session: session
      )
      user.save!
      raise ActiveRecord::Rollback
    end

    expect(user.reload.password).to eq(old_password)
    expect(described_class.where(user:)).to be_empty
    expect(PasswordEventCounter.find_by(name: 'password_change_authenticated')).to be_nil
  end

  it 'rejects unknown sources and rolls back the password update' do
    user = create_lifecycle_user!
    old_password = user.password

    expect do
      user.set_password('new-password', source: :unknown, user_session: nil)
      user.save!
    end.to raise_error(ArgumentError, /unsupported password change source/)

    expect(user.reload.password).to eq(old_password)
    expect(described_class.where(user:)).to be_empty
  end
end
