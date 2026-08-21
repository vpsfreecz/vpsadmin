# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PasswordEventCounter do
  def event(name)
    described_class.find_by!(name:)
  end

  it 'increments fixed events without moving the last occurrence backwards' do
    newer = Time.current.change(usec: 0)
    older = newer - 1.minute

    described_class.record_recovery_submission!(:accepted, at: newer)
    described_class.record_recovery_submission!(:accepted, at: older)

    recorded = event('password_recovery_submission_accepted')
    expect(recorded.event_count).to eq(2)
    expect(recorded.last_occurred_at).to eq(newer)
  end

  it 'rejects event and source names outside the fixed registry' do
    expect do
      described_class.record!(:submitted_identifier)
    end.to raise_error(ArgumentError, /unsupported password event/)

    expect do
      described_class.record_password_change!(:unknown)
    end.to raise_error(ArgumentError, /unsupported password change source/)
  end

  it 'records password changes with the selected source' do
    user = create_lifecycle_user!

    described_class::PASSWORD_CHANGE_SOURCES.each_with_index do |source, index|
      user.set_password("replacement-password-#{index}", source:)
      user.save!
    end

    described_class::PASSWORD_CHANGE_SOURCES.each do |source|
      expect(event("password_change_#{source}").event_count).to eq(1)
    end
  end

  it 'does not count account creation or a rolled-back password update' do
    expect do
      create_lifecycle_user!
    end.not_to change(described_class, :count)

    user = create_lifecycle_user!
    old_password = user.password

    User.transaction(requires_new: true) do
      user.set_password('rolled-back-password', source: :authenticated)
      user.save!
      raise ActiveRecord::Rollback
    end

    expect(user.reload.password).to eq(old_password)
    expect(described_class.find_by(name: 'password_change_authenticated')).to be_nil
  end
end
