# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PasswordChangeLog do
  def create_session(user)
    UserSession.create!(
      user:,
      auth_type: 'basic',
      api_ip_addr: '192.0.2.100',
      api_ip_ptr: 'api.example.test',
      client_ip_addr: '192.0.2.101',
      client_ip_ptr: 'client.example.test',
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
      client_ip_addr: '192.0.2.101',
      client_ip_ptr: 'client.example.test',
      user_agent_id: session.user_agent_id,
      source: 'authenticated'
    )
    expect(change.created_at).to be_present
    expect(change.user_session_owned_by_user).to be(true)
    expect(
      PasswordEventCounter.find_by!(name: 'password_change_authenticated').event_count
    ).to eq(1)
  end

  it 'records explicit client metadata without creating a session' do
    user = create_lifecycle_user!
    user_agent = UserAgent.find_or_create!('Password recovery browser')

    user.set_password(
      'new-password',
      source: :recovery,
      user_session: nil,
      client_ip_addr: '198.51.100.20',
      client_ip_ptr: 'recovery.example.test',
      user_agent:
    )
    user.save!

    expect(described_class.find_by!(user:)).to have_attributes(
      user_session_id: nil,
      client_ip_addr: '198.51.100.20',
      client_ip_ptr: 'recovery.example.test',
      user_agent_id: user_agent.id,
      source: 'recovery'
    )
    expect(described_class.find_by!(user:).user_session_owned_by_user).to be(false)
  end

  it 'allows client metadata to be unavailable for maintenance changes' do
    user = create_lifecycle_user!

    user.set_password('new-password', source: :other, user_session: nil)
    user.save!

    expect(described_class.find_by!(user:)).to have_attributes(
      user_session_id: nil,
      client_ip_addr: nil,
      client_ip_ptr: nil,
      user_agent_id: nil
    )
  end

  it 'clears client metadata when an unsaved password assignment is replaced' do
    user = create_lifecycle_user!
    user_agent = UserAgent.find_or_create!('Superseded password change')

    user.set_password(
      'superseded-password',
      source: :recovery,
      user_session: nil,
      client_ip_addr: '198.51.100.21',
      client_ip_ptr: 'superseded.example.test',
      user_agent:
    )
    user.set_password('final-password', source: :other, user_session: nil)
    user.save!

    expect(described_class.find_by!(user:)).to have_attributes(
      source: 'other',
      user_session_id: nil,
      client_ip_addr: nil,
      client_ip_ptr: nil,
      user_agent_id: nil
    )
  end

  it 'attaches only a session belonging to the affected user and never replaces it' do
    user = create_lifecycle_user!
    other_user = create_lifecycle_user!
    first_session = create_session(user)
    second_session = create_session(user)
    other_session = create_session(other_user)
    change = described_class.create!(
      user:,
      source: 'forced_reset',
      created_at: Time.current
    )

    expect do
      change.attach_user_session!(other_session)
    end.to raise_error(ArgumentError, 'user session belongs to another user')

    expect(change.attach_user_session!(first_session).user_session_id).to eq(first_session.id)
    expect(change.attach_user_session!(first_session).user_session_id).to eq(first_session.id)
    expect do
      change.attach_user_session!(second_session)
    end.to raise_error(ArgumentError, 'password change already has a user session')
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
