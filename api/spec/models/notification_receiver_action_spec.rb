# frozen_string_literal: true

require 'spec_helper'

RSpec.describe NotificationReceiverAction do
  def create_receiver!
    NotificationReceiver.create!(user: SpecSeed.user, label: 'Spec receiver')
  end

  def enable_telegram!
    allow(VpsAdmin::API::Notifications).to receive(:telegram_configured?).and_return(true)
  end

  it 'uses string columns for notification action registry names' do
    expect(described_class.type_for_attribute('action').type).to eq(:string)
    expect(EventDelivery.type_for_attribute('action').type).to eq(:string)
    expect(EventDeliveryAttempt.type_for_attribute('action').type).to eq(:string)
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
    expect(described_class.action_labels).not_to include('telegram')
  end

  it 'offers Telegram actions only when Telegram is configured' do
    expect(described_class.action_labels).not_to include('telegram')

    enable_telegram!

    expect(described_class.action_labels).to include('telegram' => 'Telegram')
  end

  it 'does not offer Telegram actions when configuration explicitly disables it' do
    allow(VpsAdmin::API::Notifications::Config).to receive(:load).and_return(
      'telegram' => {
        'enabled' => false,
        'configured' => true,
        'bot_token' => '123:telegram-token'
      }
    )

    expect(described_class.action_labels).not_to include('telegram')
  end

  it 'rejects Telegram actions when Telegram is not configured' do
    action = create_receiver!.notification_receiver_actions.build(
      action: :telegram,
      target_kind: :custom
    )

    expect(action).not_to be_valid
    expect(action.errors[:action]).to include('is not available')
  end

  it 'rejects unknown action names' do
    action = create_receiver!.notification_receiver_actions.build(
      action: 'fax',
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

  it 'clears Telegram verification when the target is edited directly' do
    enable_telegram!

    action = create_receiver!.notification_receiver_actions.create!(
      action: :telegram,
      target_kind: :custom,
      target_value: '123456',
      verified_at: Time.now
    )

    action.update!(target_value: '654321')

    expect(action).not_to be_verified
    expect(action.verification_token).to be_present
  end

  it 'keeps Telegram verification when the bot pairing method sets the target' do
    enable_telegram!

    action = create_receiver!.notification_receiver_actions.create!(
      action: :telegram,
      target_kind: :custom,
      verification_token: 'pair-token'
    )

    action.pair_telegram_chat!('987654')

    expect(action).to be_verified
    expect(action.target_value).to eq('987654')
    expect(action.verification_token).to be_nil
  end

  it 'expires pending Telegram verification tokens' do
    enable_telegram!

    action = create_receiver!.notification_receiver_actions.create!(
      action: :telegram,
      target_kind: :custom,
      verification_token: 'pair-token'
    )
    action.updated_at = Time.now - NotificationReceiverAction::VERIFICATION_TOKEN_TTL - 1

    expect(action).to be_verification_token_expired
  end

  it 'tracks Telegram verification token age independently of unrelated edits' do
    enable_telegram!

    action = create_receiver!.notification_receiver_actions.create!(
      action: :telegram,
      target_kind: :custom
    )
    action.generate_verification_token!
    action.config[NotificationReceiverAction::PAIRING_TOKEN_CREATED_AT_KEY] =
      (Time.now - NotificationReceiverAction::VERIFICATION_TOKEN_TTL - 1).iso8601
    action.save!

    action.update!(label: 'Updated label')

    expect(action).to be_verification_token_expired
  end
end
