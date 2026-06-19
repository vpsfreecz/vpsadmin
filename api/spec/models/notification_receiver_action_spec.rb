# frozen_string_literal: true

require 'spec_helper'

RSpec.describe NotificationReceiverAction do
  def create_receiver!
    NotificationReceiver.create!(user: SpecSeed.user, label: 'Spec receiver')
  end

  it 'stores actions as registry names' do
    action = create_receiver!.notification_receiver_actions.create!(
      action: :webhook,
      target_kind: :custom,
      target_value: 'https://example.test/events'
    )

    expect(action.action).to eq('webhook')
    expect(action).to be_webhook_action
    expect(described_class.action_labels).to include(
      'email' => 'E-mail',
      'webhook' => 'Webhook'
    )
  end

  it 'rejects unknown action names' do
    action = create_receiver!.notification_receiver_actions.build(
      action: 'telegram',
      target_kind: :custom,
      target_value: 'https://example.test/events'
    )

    expect(action).not_to be_valid
    expect(action.errors[:action]).to be_present
  end

  it 'normalizes custom e-mail targets' do
    action = create_receiver!.notification_receiver_actions.create!(
      action: :email,
      target_kind: :custom,
      target_value: " audit@example.test,\nops@example.test "
    )

    expect(action.target_value).to eq('audit@example.test,ops@example.test')
  end

  it 'rejects custom e-mail targets that exceed mail log limits' do
    action = create_receiver!.notification_receiver_actions.build(
      action: :email,
      target_kind: :custom,
      target_value: "#{'a' * NotificationReceiverAction::MAIL_TARGET_VALUE_LIMIT}@example.test"
    )

    expect(action).not_to be_valid
    expect(action.errors[:target_value]).to include(
      "is too long (maximum is #{NotificationReceiverAction::MAIL_TARGET_VALUE_LIMIT} characters)"
    )
  end
end
