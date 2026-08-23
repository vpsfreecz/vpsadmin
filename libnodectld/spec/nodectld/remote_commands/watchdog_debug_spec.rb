# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/remote_control'
require 'nodectld/remote_commands/base'
require 'nodectld/remote_commands/watchdog_debug'

RSpec.describe NodeCtld::RemoteCommands::WatchdogDebug do
  it 'returns the transaction-loop thread state and backtrace' do
    thread = instance_double(
      Thread,
      status: 'sleep',
      backtrace: ['daemon.rb:123:in `check_commands?`']
    )
    daemon = instance_double(
      NodeCtldSpec::FakeDaemon,
      transaction_thread: thread,
      last_transaction_check_monotonic: 34.5
    )

    expect(described_class.new({}, daemon).exec).to eq(
      ret: :ok,
      output: {
        last_transaction_check_monotonic: 34.5,
        transaction_thread: {
          status: 'sleep',
          backtrace: ['daemon.rb:123:in `check_commands?`']
        }
      }
    )
  end
end
