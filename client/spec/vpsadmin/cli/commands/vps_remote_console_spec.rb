# frozen_string_literal: true

require 'spec_helper'

class ConsoleHttpClientSpy
  def write(_data); end
end

RSpec.describe VpsAdmin::CLI::Commands::VpsRemoteControl::InputHandler do
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
