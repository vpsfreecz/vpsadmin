# frozen_string_literal: true

require 'spec_helper'

RSpec.describe NotificationReceiverAction do
  def create_receiver!
    NotificationReceiver.create!(user: SpecSeed.user, label: 'Spec receiver')
  end

  def enable_telegram!
    allow(VpsAdmin::API::Notifications).to receive(:telegram_configured?).and_return(true)
  end

  def enable_sms!
    allow(VpsAdmin::API::Notifications).to receive(:sms_configured?).and_return(true)
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

  it 'offers SMS actions only when SMS is configured' do
    expect(described_class.action_labels).not_to include('sms')

    enable_sms!

    expect(described_class.action_labels).to include('sms' => 'SMS')
  end

  it 'rejects SMS actions when SMS is not enabled for the user' do
    allow(VpsAdmin::API::Notifications).to receive(:sms_configured?).and_return(true)
    SpecSeed.user.set_notification_delivery_method!(:sms, false)

    action = create_receiver!.notification_receiver_actions.build(
      action: :sms,
      target_kind: :custom,
      target_value: '+420123456789'
    )

    expect(action).not_to be_valid
    expect(action.errors[:action]).to include('is not enabled for this user')
  end

  it 'rejects actions when their delivery method is disabled for the user' do
    %i[email webhook].each do |delivery_method|
      SpecSeed.user.set_notification_delivery_method!(delivery_method, false)

      action = create_receiver!.notification_receiver_actions.build(
        action: delivery_method,
        target_kind: delivery_method == :email ? :default_recipient : :custom,
        target_value: delivery_method == :webhook ? 'https://example.test/events' : nil
      )

      expect(action).not_to be_valid
      expect(action.errors[:action]).to include('is not enabled for this user')

      SpecSeed.user.set_notification_delivery_method!(delivery_method, true)
    end
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
      target_value: ' Audit Target <audit@example.test> '
    )

    expect(action.target_value).to eq('audit@example.test')
  end

  it 'rejects custom e-mail targets with multiple addresses' do
    [
      'audit@example.test,ops@example.test',
      'audit@example.test;ops@example.test',
      'root,audit@example.test',
      'root; audit@example.test',
      'audit@example.test;root'
    ].each do |target_value|
      action = create_receiver!.notification_receiver_actions.build(
        action: :email,
        target_kind: :custom,
        target_value:
      )

      expect(action).not_to be_valid
      expect(action.errors[:target_value]).to include('must contain one e-mail address')
    end
  end

  it 'rejects local-only custom e-mail targets' do
    %w[bad root].each do |target_value|
      action = create_receiver!.notification_receiver_actions.build(
        action: :email,
        target_kind: :custom,
        target_value:
      )

      expect(action).not_to be_valid
      expect(action.errors[:target_value]).to include("'#{target_value}' is not a valid e-mail address")
    end
  end

  it 'uses compact identity keys for long custom e-mail targets' do
    target_value = "#{'a' * 470}@example.test"
    action = create_receiver!.notification_receiver_actions.create!(
      action: :email,
      target_kind: :custom,
      target_value:
    )

    duplicate = create_receiver!.notification_receiver_actions.create!(
      action: :email,
      target_kind: :custom,
      target_value:
    )

    expect(action.target_value).to eq(target_value)
    expect(action.identity_key).to eq("custom:#{Digest::SHA256.hexdigest(target_value)}")
    expect(action.identity_key.length).to be < 255
    expect(duplicate.notification_target).to eq(action.notification_target)
  end

  it 'uses compact identity keys for long webhook URLs and secret variants' do
    target_value = "https://example.test/#{'events/' * 40}"
    first = create_receiver!.notification_receiver_actions.create!(
      action: :webhook,
      target_kind: :custom,
      target_value:,
      secret: 'first'
    )
    second = create_receiver!.notification_receiver_actions.create!(
      action: :webhook,
      target_kind: :custom,
      target_value:,
      secret: 'second'
    )

    expect(first.target_value).to eq(target_value)
    expect(first.identity_key).to eq("url:#{Digest::SHA256.hexdigest("#{target_value}\0first")}")
    expect(first.identity_key.length).to be < 255
    expect(second.target_value).to eq(target_value)
    expect(second.identity_key).to eq("url:#{Digest::SHA256.hexdigest("#{target_value}\0second")}")
    expect(second.notification_target).not_to eq(first.notification_target)
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

  it 'verifies custom e-mail targets using hidden tokens' do
    action = create_receiver!.notification_receiver_actions.create!(
      action: :email,
      target_kind: :custom,
      target_value: 'audit@example.test'
    )
    action.generate_email_verification_token!
    token = action[:verification_token]

    expect(action.verification_token).to be_nil
    expect(token).to be_present
    expect(action.confirm_email_verification_token!('invalid')).to be(false)
    expect(action.reload.confirm_email_verification_token!(token)).to be(true)
    expect(action).to be_verified
    expect(action[:verification_token]).to be_nil
  end

  it 'clears custom e-mail verification when the address is edited' do
    action = create_receiver!.notification_receiver_actions.create!(
      action: :email,
      target_kind: :custom,
      target_value: 'audit@example.test',
      verified_at: Time.now
    )

    action.update!(target_value: 'ops@example.test')

    expect(action.reload).not_to be_verified
    expect(action[:verification_token]).to be_present
  end

  it 'verifies SMS numbers using hidden short-lived codes' do
    enable_sms!

    action = create_receiver!.notification_receiver_actions.create!(
      action: :sms,
      target_kind: :custom,
      target_value: '+420123456789'
    )
    action.generate_sms_verification_code!
    code = action[:verification_token]

    expect(action.verification_token).to be_nil
    expect(code).to match(/\A[0-9]{6}\z/)
    expect(action.confirm_sms_verification_code!(code)).to be(true)
    expect(action).to be_verified
    expect(action[:verification_token]).to be_nil
  end

  it 'locks SMS verification after repeated invalid codes' do
    enable_sms!

    action = create_receiver!.notification_receiver_actions.create!(
      action: :sms,
      target_kind: :custom,
      target_value: '+420123456789'
    )
    action.generate_sms_verification_code!
    code = action[:verification_token]
    invalid_code = code == '000000' ? '000001' : '000000'

    NotificationReceiverAction::SMS_VERIFICATION_MAX_FAILED_ATTEMPTS.times do
      expect(action.confirm_sms_verification_code!(invalid_code)).to be(false)
      action.reload
    end

    expect(action).to be_sms_verification_locked
    expect(action.confirm_sms_verification_code!(code)).to be(false)
    expect(action.reload).not_to be_verified
  end

  it 'clears SMS verification when the phone number is edited' do
    enable_sms!

    action = create_receiver!.notification_receiver_actions.create!(
      action: :sms,
      target_kind: :custom,
      target_value: '+420123456789',
      verified_at: Time.now
    )

    action.update!(target_value: '+420987654321')

    expect(action).not_to be_verified
    expect(action[:verification_token]).to match(/\A[0-9]{6}\z/)
    expect(action.verification_token).to be_nil
  end

  it 'expires pending SMS verification codes quickly' do
    enable_sms!

    action = create_receiver!.notification_receiver_actions.create!(
      action: :sms,
      target_kind: :custom,
      target_value: '+420123456789'
    )
    action.generate_sms_verification_code!
    action.config[NotificationReceiverAction::SMS_VERIFICATION_CODE_CREATED_AT_KEY] =
      (Time.now - NotificationReceiverAction::SMS_VERIFICATION_CODE_TTL - 1).iso8601
    action.save!

    expect(action).to be_verification_token_expired
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

  it 'builds Telegram pairing links from configured bot username' do
    enable_telegram!
    allow(VpsAdmin::API::Notifications::Config).to receive(:load).and_return(
      'telegram' => {
        'bot_username' => '@vpsadmin_aitherdev_bot'
      }
    )

    action = create_receiver!.notification_receiver_actions.create!(
      action: :telegram,
      target_kind: :custom,
      verification_token: 'pair-token'
    )

    expect(action.telegram_pairing_command).to eq('/start pair-token')
    expect(action.telegram_bot_url).to eq('https://t.me/vpsadmin_aitherdev_bot')
    expect(action.telegram_pairing_url).to eq('https://t.me/vpsadmin_aitherdev_bot?start=pair-token')
  end

  it 'omits Telegram pairing links when the bot username is not configured' do
    enable_telegram!

    action = create_receiver!.notification_receiver_actions.create!(
      action: :telegram,
      target_kind: :custom,
      verification_token: 'pair-token'
    )

    expect(action.telegram_pairing_command).to eq('/start pair-token')
    expect(action.telegram_bot_url).to be_nil
    expect(action.telegram_pairing_url).to be_nil
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
