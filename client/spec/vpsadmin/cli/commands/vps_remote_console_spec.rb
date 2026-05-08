# frozen_string_literal: true

require 'spec_helper'

class ConsoleHttpClientSpy
  def write(_data); end
end

class FakeConsoleHttp
  attr_reader :last_request

  def initialize(response)
    @response = response
  end

  def request(req)
    @last_request = req
    @response
  end
end

class FakeConsoleSuccess < Net::HTTPSuccess
  def initialize(body)
    super('1.1', '200', 'OK')
    @body = body
  end

  attr_reader :body
end

RSpec.describe VpsAdmin::CLI::Commands::VpsRemoteControl do
  describe described_class::InputHandler do
    let(:client) { instance_spy(ConsoleHttpClientSpy) }
    let(:handler) { described_class.new(client) }

    it 'forwards regular input' do
      handler.send(:write, 'abc')

      expect(client).to have_received(:write).with('abc')
      expect(handler).not_to be_stop
    end

    it 'flushes a broken escape sequence' do
      handler.send(:write, "\r\eX")

      expect(client).to have_received(:write).with("\r\eX")
      expect(handler).not_to be_stop
    end

    it 'flushes buffered forwarded input before stopping' do
      handler.send(:write, "abc\r\e.")

      expect(client).to have_received(:write).with("abc\r")
      expect(handler).to be_stop
    end
  end

  describe described_class::HttpClient do
    def ok_response(body)
      FakeConsoleSuccess.new(body)
    end

    it 'posts buffered keys and writes decoded console output' do
      client = described_class.new(FakeRecord.new, 'session-token', 0.05)
      http = FakeConsoleHttp.new(
        ok_response(JSON.dump(session: true, data: Base64.encode64('console output')))
      )

      client.resize(120, 40)
      client.write('abc')

      output = capture_stdout do
        client.send(:send_request, http, URI('http://console.example.test/console/feed/55'))
      end

      form = URI.decode_www_form(http.last_request.body).to_h

      expect(form).to include(
        'session' => 'session-token',
        'keys' => 'abc',
        'width' => '120',
        'height' => '40'
      )
      expect(output).to eq('console output')
    end

    it 'marks the session closed when the console server returns no session' do
      client = described_class.new(FakeRecord.new, 'session-token', 0.05)
      http = FakeConsoleHttp.new(
        ok_response(JSON.dump(session: false, data: 'closed by server'))
      )

      output = capture_stdout do
        client.send(:send_request, http, URI('http://console.example.test/console/feed/55'))
      end

      expect(output).to eq('closed by server')
      expect(client).to be_error
      expect(client).to be_stop
    end
  end
end
