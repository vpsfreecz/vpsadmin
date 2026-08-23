# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/remote_control'
require 'nodectld/remote_commands/base'
require 'nodectld/remote_commands/watchdog_status'

RSpec.describe NodeCtld::RemoteCommands::WatchdogStatus do
  it 'returns transaction-poll timestamps without accessing the database' do
    daemon = instance_double(
      NodeCtldSpec::FakeDaemon,
      start_monotonic: 12.5,
      last_transaction_check_monotonic: 34.5
    )

    expect(described_class.new({}, daemon).exec).to eq(
      ret: :ok,
      output: {
        start_monotonic: 12.5,
        last_transaction_check_monotonic: 34.5
      }
    )
  end
end
