# frozen_string_literal: true

require 'spec_helper'
require 'socket'
require 'nodectld/remote_control'
require 'nodectld/remote_commands/base'

class RemoteControlSpecOkCommand < NodeCtld::RemoteCommands::Base
  def exec
    { ret: :ok, output: { answer: 42 } }
  end
end

class RemoteControlSpecFailedCommand < NodeCtld::RemoteCommands::Base
  def exec
    { ret: :failed, output: 'nope' }
  end
end

class RemoteControlSpecRemoteErrorCommand < NodeCtld::RemoteCommands::Base
  def exec
    raise NodeCtld::RemoteCommandError, 'remote failed'
  end
end

class RemoteControlSpecSystemErrorCommand < NodeCtld::RemoteCommands::Base
  def exec
    raise NodeCtld::SystemCommandFailed.new('spec-cmd', 17, 'system failed')
  end
end

RSpec.describe NodeCtld::RemoteControl::Client do
  around do |example|
    handlers = NodeCtld::RemoteControl.handlers.dup

    NodeCtld::RemoteControl.handlers.clear
    NodeCtld::RemoteControl.register('RemoteControlSpecOkCommand', :spec_ok)
    NodeCtld::RemoteControl.register('RemoteControlSpecFailedCommand', :spec_failed)
    NodeCtld::RemoteControl.register('RemoteControlSpecRemoteErrorCommand', :spec_remote_error)
    NodeCtld::RemoteControl.register('RemoteControlSpecSystemErrorCommand', :spec_system_error)

    example.run
  ensure
    NodeCtld::RemoteControl.handlers.clear
    handlers.each { |name, klass| NodeCtld::RemoteControl.handlers[name] = klass }
  end

  def exchange(request)
    server, client = UNIXSocket.pair
    thread = Thread.new { described_class.new(server, :daemon).communicate }
    greeting = JSON.parse(client.gets, symbolize_names: true)

    client.puts(request)
    reply = JSON.parse(client.gets, symbolize_names: true)
    client.close
    thread.join
    server.close

    [greeting, reply]
  end

  it 'sends a greeting before request processing' do
    greeting, reply = exchange({ command: :spec_ok }.to_json)

    expect(greeting).to eq(version: NodeCtld::VERSION)
    expect(reply).to eq(status: 'ok', response: { answer: 42 })
  end

  it 'returns a structured failure for malformed JSON' do
    _greeting, reply = exchange('{')

    expect(reply).to eq(status: 'failed', error: 'Syntax error')
  end

  it 'returns a structured failure for unsupported commands' do
    _greeting, reply = exchange({ command: :missing }.to_json)

    expect(reply).to eq(status: 'failed', error: 'Unsupported command')
  end

  it 'wraps failed command returns' do
    _greeting, reply = exchange({ command: :spec_failed }.to_json)

    expect(reply).to eq(status: 'failed', error: 'nope')
  end

  it 'wraps remote command errors' do
    _greeting, reply = exchange({ command: :spec_remote_error }.to_json)

    expect(reply).to eq(status: 'failed', error: 'remote failed')
  end

  it 'wraps system command failures with command metadata' do
    _greeting, reply = exchange({ command: :spec_system_error }.to_json)

    expect(reply).to eq(
      status: 'failed',
      error: {
        cmd: 'spec-cmd',
        exitstatus: 17,
        error: 'system failed'
      }
    )
  end
end
