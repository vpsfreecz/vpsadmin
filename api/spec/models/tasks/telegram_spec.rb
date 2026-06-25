# frozen_string_literal: true

require 'spec_helper'
require 'rack/mock'

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
    NotificationTarget.where(user: SpecSeed.user).delete_all
    NotificationReceiver.where(user: SpecSeed.user).delete_all
    SysConfig.where(category: 'notifications', name: 'telegram_update_offset').delete_all
  end

  def create_telegram_action!(token: 'pair-token')
    allow(VpsAdmin::API::Notifications).to receive(:telegram_configured?).and_return(true)

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

  def stub_telegram_updates(
    code: '200',
    body: { ok: true, result: [] },
    read_timeout: 55,
    message_code: '200',
    message_body: { ok: true, result: true }
  )
    requests = []
    updates_response = instance_double(Net::HTTPResponse, code:, body: JSON.dump(body))
    message_response = instance_double(Net::HTTPResponse, code: message_code, body: JSON.dump(message_body))

    allow(Net::HTTP).to receive(:start) do |host, port, **options, &block|
      expect(host).to eq('api.telegram.org')
      expect(port).to eq(443)
      expect(options).to include(
        use_ssl: true,
        open_timeout: 5
      )

      http = instance_double(Net::HTTP)
      allow(http).to receive(:request) do |req|
        requests << { request: req, options: }
        req.path.end_with?('/sendMessage') ? message_response : updates_response
      end
      block.call(http)
    end

    requests
  end

  it 'pairs Telegram actions from private /start messages' do
    action = create_telegram_action!
    requests = stub_telegram_updates(
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

    updates_request = requests[0].fetch(:request)
    reply_request = requests[1].fetch(:request)
    body = JSON.parse(updates_request.body)

    expect(updates_request.path).to eq('/bot123:telegram-token/getUpdates')
    expect(requests[0].fetch(:options)).to include(read_timeout: 55)
    expect(body).to include(
      'allowed_updates' => ['message'],
      'limit' => 100,
      'timeout' => 50
    )
    expect(body).not_to have_key('offset')
    expect(reply_request.path).to eq('/bot123:telegram-token/sendMessage')
    expect(JSON.parse(reply_request.body)).to include(
      'chat_id' => 987_654,
      'text' => /pairing succeeded/
    )
    expect(stats).to eq(paired: 1, rejected: 0, ignored: 0)
    expect(action.reload).to be_verified
    expect(action.target_value).to eq('987654')
    expect(action.verification_token).to be_nil
    expect(action.last_error).to be_nil
    expect(SysConfig.get('notifications', 'telegram_update_offset')).to eq(43)
  end

  it 'verifies an existing duplicate Telegram target when pairing succeeds' do
    allow(VpsAdmin::API::Notifications).to receive(:telegram_configured?).and_return(true)

    existing = NotificationTarget.create!(
      user: SpecSeed.user,
      action: 'telegram',
      label: 'Existing Telegram',
      target_kind: 'custom',
      target_value: '987654',
      verification_token: 'old-token'
    )
    action = create_telegram_action!
    receiver = action.notification_receiver
    pending_target_id = action.notification_target_id
    stub_telegram_updates(
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

    expect(stats).to eq(paired: 1, rejected: 0, ignored: 0)
    expect(existing.reload).to be_verified
    expect(existing.target_value).to eq('987654')
    expect(existing.verification_token).to be_nil
    expect(receiver.notification_receiver_targets.reload.sole.notification_target).to eq(existing)
    expect(NotificationTarget.exists?(pending_target_id)).to be(false)
  end

  it 'replies with pairing instructions when /start has no token' do
    requests = stub_telegram_updates(
      body: {
        ok: true,
        result: [
          update(update_id: 41, text: '/start')
        ]
      }
    )

    stats = with_env('VPSADMIN_TELEGRAM_BOT_TOKEN' => '123:telegram-token') do
      task.poll_pairing_updates
    end

    expect(JSON.parse(requests[1].fetch(:request).body)).to include(
      'chat_id' => 123_456,
      'text' => /open the Telegram action detail/
    )
    expect(stats).to eq(paired: 0, rejected: 1, ignored: 0)
    expect(SysConfig.get('notifications', 'telegram_update_offset')).to eq(42)
  end

  it 'replies when a pairing token is invalid' do
    create_telegram_action!(token: 'other-token')
    requests = stub_telegram_updates(
      body: {
        ok: true,
        result: [
          update(update_id: 41, text: '/start wrong-token')
        ]
      }
    )

    stats = with_env('VPSADMIN_TELEGRAM_BOT_TOKEN' => '123:telegram-token') do
      task.poll_pairing_updates
    end

    expect(JSON.parse(requests[1].fetch(:request).body)).to include(
      'chat_id' => 123_456,
      'text' => /not valid/
    )
    expect(stats).to eq(paired: 0, rejected: 1, ignored: 0)
  end

  it 'keeps pairing when the Telegram reply fails' do
    action = create_telegram_action!
    stub_telegram_updates(
      body: {
        ok: true,
        result: [
          update(update_id: 42, text: '/start pair-token')
        ]
      },
      message_code: '500',
      message_body: { ok: false, description: 'Internal error' }
    )

    stats = with_env('VPSADMIN_TELEGRAM_BOT_TOKEN' => '123:telegram-token') do
      task.poll_pairing_updates
    end

    expect(stats).to eq(paired: 1, rejected: 0, ignored: 0)
    expect(action.reload).to be_verified
    expect(SysConfig.get('notifications', 'telegram_update_offset')).to eq(43)
  end

  it 'uses the saved update offset and configured polling bounds' do
    SysConfig.create!(
      category: 'notifications',
      name: 'telegram_update_offset',
      value: 123
    )
    requests = stub_telegram_updates(read_timeout: 15)

    stats = with_env(
      'VPSADMIN_TELEGRAM_BOT_TOKEN' => '123:telegram-token',
      'VPSADMIN_TELEGRAM_UPDATES_LIMIT' => '2',
      'VPSADMIN_TELEGRAM_UPDATES_TIMEOUT' => '10'
    ) do
      task.poll_pairing_updates
    end

    body = JSON.parse(requests[0].fetch(:request).body)

    expect(body).to include(
      'offset' => 123,
      'limit' => 2,
      'timeout' => 10
    )
    expect(requests[0].fetch(:options)).to include(read_timeout: 15)
    expect(stats).to eq(paired: 0, rejected: 0, ignored: 0)
  end

  it 'keeps the HTTP read timeout above the Telegram long-poll timeout' do
    requests = stub_telegram_updates(read_timeout: 55)

    with_env(
      'VPSADMIN_TELEGRAM_BOT_TOKEN' => '123:telegram-token',
      'VPSADMIN_TELEGRAM_UPDATES_TIMEOUT' => '999'
    ) do
      task.poll_pairing_updates
    end

    expect(JSON.parse(requests[0].fetch(:request).body)).to include('timeout' => 50)
    expect(requests[0].fetch(:options)).to include(read_timeout: 55)
  end

  it 'deletes webhooks before polling starts' do
    bot = instance_double(VpsAdmin::API::TelegramBot)
    response = instance_double(
      Net::HTTPResponse,
      code: '200',
      body: JSON.dump(ok: true, result: true)
    )
    receiver = VpsAdmin::API::TelegramReceiver.new(
      bot:,
      config: {
        'telegram' => {
          'polling' => {
            'delete_webhook' => true
          }
        }
      }
    )

    allow(bot).to receive(:post_json)
      .with('deleteWebhook', { drop_pending_updates: false })
      .and_return(response)

    receiver.send(:prepare_polling!)

    expect(bot).to have_received(:post_json)
      .with('deleteWebhook', { drop_pending_updates: false })
  end

  it 'rejects pairing attempts from non-private chats' do
    action = create_telegram_action!
    original_token = action.verification_token
    requests = stub_telegram_updates(
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

    expect(JSON.parse(requests[1].fetch(:request).body)).to include(
      'chat_id' => 123_456,
      'text' => /private chat/
    )
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
    action.notification_target.update!(
      config: (action.config || {}).merge(
        NotificationReceiverAction::PAIRING_TOKEN_CREATED_AT_KEY =>
          (Time.now - NotificationReceiverAction::VERIFICATION_TOKEN_TTL - 60).iso8601
      )
    )
    requests = stub_telegram_updates(
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

    expect(JSON.parse(requests[1].fetch(:request).body)).to include(
      'chat_id' => 123_456,
      'text' => /expired/
    )
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

  it 'pairs Telegram actions from webhook updates' do
    action = create_telegram_action!
    receiver = VpsAdmin::API::TelegramReceiver.new(
      config: {
        'telegram' => {
          'webhook' => {
            'path' => '/_telegram/webhook',
            'secret_token' => 'webhook-secret'
          }
        }
      }
    )
    request = Rack::MockRequest.new(receiver.webhook_app)

    response = request.post(
      '/_telegram/webhook',
      'CONTENT_TYPE' => 'application/json',
      'HTTP_X_TELEGRAM_BOT_API_SECRET_TOKEN' => 'webhook-secret',
      input: JSON.dump(update(update_id: 45, text: '/start pair-token', chat_id: 222_333))
    )

    expect(response.status).to eq(200)
    expect(JSON.parse(response.body)).to include('ok' => true)
    expect(action.reload).to be_verified
    expect(action.target_value).to eq('222333')
    expect(SysConfig.get('notifications', 'telegram_update_offset')).to be_nil
  end

  it 'rejects webhook updates with an invalid secret token' do
    action = create_telegram_action!
    receiver = VpsAdmin::API::TelegramReceiver.new(
      config: {
        'telegram' => {
          'webhook' => {
            'path' => '/_telegram/webhook',
            'secret_token' => 'webhook-secret'
          }
        }
      }
    )
    request = Rack::MockRequest.new(receiver.webhook_app)

    response = request.post(
      '/_telegram/webhook',
      'CONTENT_TYPE' => 'application/json',
      'HTTP_X_TELEGRAM_BOT_API_SECRET_TOKEN' => 'wrong',
      input: JSON.dump(update(update_id: 46, text: '/start pair-token'))
    )

    expect(response.status).to eq(403)
    expect(action.reload).not_to be_verified
  end
end
