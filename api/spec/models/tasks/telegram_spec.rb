# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Tasks::Telegram do
  around do |example|
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  let(:task) { described_class.new }

  before do
    NotificationReceiverAction
      .joins(:notification_receiver)
      .where(notification_receivers: { user_id: SpecSeed.user.id })
      .delete_all
    NotificationReceiver.where(user: SpecSeed.user).delete_all
    SysConfig.where(category: 'notifications', name: 'telegram_update_offset').delete_all
  end

  def create_telegram_action!(token: 'pair-token')
    receiver = NotificationReceiver.create!(user: SpecSeed.user, label: 'Spec Telegram receiver')
    receiver.notification_receiver_actions.create!(
      action: :telegram,
      label: 'Spec Telegram',
      target_kind: :custom,
      verification_token: token
    )
  end

  def update(update_id:, text:, chat_id: 123_456, chat_type: 'private')
    {
      update_id:,
      message: {
        message_id: update_id,
        text:,
        chat: {
          id: chat_id,
          type: chat_type
        }
      }
    }
  end

  def stub_telegram_updates(code: '200', body: { ok: true, result: [] }, read_timeout: 15)
    request = nil
    http = instance_double(Net::HTTP)
    response = instance_double(Net::HTTPResponse, code:, body: JSON.dump(body))

    allow(Net::HTTP).to receive(:start) do |host, port, **options, &block|
      expect(host).to eq('api.telegram.org')
      expect(port).to eq(443)
      expect(options).to include(
        use_ssl: true,
        open_timeout: 5,
        read_timeout:
      )

      block.call(http)
    end
    allow(http).to receive(:request) do |req|
      request = req
      response
    end

    -> { request }
  end

  it 'pairs Telegram actions from private /start messages' do
    action = create_telegram_action!
    request = stub_telegram_updates(
      body: {
        ok: true,
        result: [
          update(update_id: 42, text: '/start pair-token', chat_id: 987_654)
        ]
      }
    )

    stats = with_env('VPSADMIN_TELEGRAM_BOT_TOKEN' => '123:telegram-token') do
      task.poll_pairing_updates
    end

    body = JSON.parse(request.call.body)

    expect(request.call.path).to eq('/bot123:telegram-token/getUpdates')
    expect(body).to include(
      'allowed_updates' => ['message'],
      'limit' => 100,
      'timeout' => 0
    )
    expect(body).not_to have_key('offset')
    expect(stats).to eq(paired: 1, rejected: 0, ignored: 0)
    expect(action.reload).to be_verified
    expect(action.target_value).to eq('987654')
    expect(action.verification_token).to be_nil
    expect(action.last_error).to be_nil
    expect(SysConfig.get('notifications', 'telegram_update_offset')).to eq(43)
  end

  it 'uses the saved update offset and configured polling bounds' do
    SysConfig.create!(
      category: 'notifications',
      name: 'telegram_update_offset',
      value: 123
    )
    request = stub_telegram_updates

    stats = with_env(
      'VPSADMIN_TELEGRAM_BOT_TOKEN' => '123:telegram-token',
      'VPSADMIN_TELEGRAM_UPDATES_LIMIT' => '2',
      'VPSADMIN_TELEGRAM_UPDATES_TIMEOUT' => '10'
    ) do
      task.poll_pairing_updates
    end

    body = JSON.parse(request.call.body)

    expect(body).to include(
      'offset' => 123,
      'limit' => 2,
      'timeout' => 10
    )
    expect(stats).to eq(paired: 0, rejected: 0, ignored: 0)
  end

  it 'keeps the HTTP read timeout above the Telegram long-poll timeout' do
    request = stub_telegram_updates(read_timeout: 55)

    with_env(
      'VPSADMIN_TELEGRAM_BOT_TOKEN' => '123:telegram-token',
      'VPSADMIN_TELEGRAM_UPDATES_TIMEOUT' => '999'
    ) do
      task.poll_pairing_updates
    end

    expect(JSON.parse(request.call.body)).to include('timeout' => 50)
  end

  it 'rejects pairing attempts from non-private chats' do
    action = create_telegram_action!
    original_token = action.verification_token
    stub_telegram_updates(
      body: {
        ok: true,
        result: [
          update(update_id: 43, text: '/start pair-token', chat_type: 'group')
        ]
      }
    )

    stats = with_env('VPSADMIN_TELEGRAM_BOT_TOKEN' => '123:telegram-token') do
      task.poll_pairing_updates
    end

    action.reload

    expect(stats).to eq(paired: 0, rejected: 1, ignored: 0)
    expect(action).not_to be_verified
    expect(action.target_value).to be_nil
    expect(action.verification_token).to be_present
    expect(action.verification_token).not_to eq(original_token)
    expect(action.last_error).to include('private chat')
    expect(SysConfig.get('notifications', 'telegram_update_offset')).to eq(44)
  end

  it 'rejects expired pairing tokens and rotates them' do
    action = create_telegram_action!
    original_token = action.verification_token
    action.update_column(
      :updated_at,
      Time.now - NotificationReceiverAction::VERIFICATION_TOKEN_TTL - 60
    )
    stub_telegram_updates(
      body: {
        ok: true,
        result: [
          update(update_id: 44, text: '/start pair-token')
        ]
      }
    )

    stats = with_env('VPSADMIN_TELEGRAM_BOT_TOKEN' => '123:telegram-token') do
      task.poll_pairing_updates
    end

    action.reload

    expect(stats).to eq(paired: 0, rejected: 1, ignored: 0)
    expect(action).not_to be_verified
    expect(action.target_value).to be_nil
    expect(action.verification_token).to be_present
    expect(action.verification_token).not_to eq(original_token)
    expect(action.last_error).to include('expired')
    expect(SysConfig.get('notifications', 'telegram_update_offset')).to eq(45)
  end

  it 'does not advance the offset when Telegram returns an error' do
    create_telegram_action!
    SysConfig.create!(
      category: 'notifications',
      name: 'telegram_update_offset',
      value: 50
    )
    stub_telegram_updates(
      code: '409',
      body: {
        ok: false,
        description: 'Conflict: terminated by other getUpdates request'
      }
    )

    expect do
      with_env('VPSADMIN_TELEGRAM_BOT_TOKEN' => '123:telegram-token') do
        task.poll_pairing_updates
      end
    end.to raise_error(RuntimeError, /terminated by other getUpdates request/)

    expect(SysConfig.get('notifications', 'telegram_update_offset')).to eq(50)
  end
end
