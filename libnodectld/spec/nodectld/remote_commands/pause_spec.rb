# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/remote_control'
require 'nodectld/remote_commands/base'
require 'nodectld/remote_commands/pause'

RSpec.describe NodeCtld::RemoteCommands::Pause do
  it 'pauses the daemon when no transaction id is provided' do
    daemon = instance_spy(NodeCtldSpec::FakeDaemon)

    expect(described_class.new({}, daemon).exec).to eq(ret: :ok)
    expect(daemon).to have_received(:pause).with(true)
  end

  it 'pauses after a specific transaction id' do
    daemon = instance_spy(NodeCtldSpec::FakeDaemon)

    expect(described_class.new({ t_id: 123 }, daemon).exec).to eq(ret: :ok)
    expect(daemon).to have_received(:pause).with(123)
  end
end
