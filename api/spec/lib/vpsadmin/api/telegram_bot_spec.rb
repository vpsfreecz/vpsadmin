# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe VpsAdmin::API::TelegramBot do
  def stub_telegram_response
    request = nil
    http = instance_double(Net::HTTP)
    response = instance_double(Net::HTTPResponse, code: '200', body: '{"ok":true}')

    allow(Net::HTTP).to receive(:start) do |host, port, **options, &block|
      expect(host).to eq('api.telegram.org')
      expect(port).to eq(443)
      expect(options).to include(
        use_ssl: true,
        open_timeout: 5,
        read_timeout: 15
      )

      block.call(http)
    end
    allow(http).to receive(:request) do |req|
      request = req
      response
    end

    -> { request }
  end

  it 'reads the bot token from a configured token file' do
    request = stub_telegram_response

    Dir.mktmpdir('vpsadmin-telegram-bot-spec') do |dir|
      token_file = File.join(dir, 'token')
      File.write(token_file, "123:file-token\n")

      with_env(
        'VPSADMIN_TELEGRAM_BOT_TOKEN' => nil,
        'VPSADMIN_TELEGRAM_BOT_TOKEN_FILE' => token_file
      ) do
        described_class.new.post_json('sendMessage', { chat_id: 1, text: 'hello' })
      end
    end

    expect(request.call.path).to eq('/bot123:file-token/sendMessage')
  end

  it 'prefers an explicit token over the configured token file' do
    request = stub_telegram_response

    Dir.mktmpdir('vpsadmin-telegram-bot-spec') do |dir|
      token_file = File.join(dir, 'token')
      File.write(token_file, "123:file-token\n")

      with_env('VPSADMIN_TELEGRAM_BOT_TOKEN_FILE' => token_file) do
        described_class.new(token: '123:explicit-token')
                       .post_json('sendMessage', { chat_id: 1, text: 'hello' })
      end
    end

    expect(request.call.path).to eq('/bot123:explicit-token/sendMessage')
  end

  it 'reads the token and API URL from notification config' do
    request = nil
    http = instance_double(Net::HTTP)
    response = instance_double(Net::HTTPResponse, code: '200', body: '{"ok":true}')

    allow(Net::HTTP).to receive(:start) do |host, port, **options, &block|
      expect(host).to eq('api.telegram.org')
      expect(port).to eq(443)
      expect(options).to include(use_ssl: true)
      block.call(http)
    end
    allow(http).to receive(:request) do |req|
      request = req
      response
    end

    described_class.new(
      config: {
        'bot_token' => '123:config-token',
        'api_base_url' => 'https://api.telegram.org/'
      }
    ).post_json('sendMessage', { chat_id: 1, text: 'hello' })

    expect(request.path).to eq('/bot123:config-token/sendMessage')
  end
end
