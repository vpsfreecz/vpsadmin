# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/remote_control'
require 'nodectld/remote_commands/base'
require 'nodectld/remote_commands/refresh'

RSpec.describe NodeCtld::RemoteCommands::Refresh do
  it 'updates all runtime resources' do
    daemon = instance_spy(NodeCtldSpec::FakeDaemon)
    cmd = described_class.new({}, daemon)

    allow(cmd).to receive(:log)

    expect(cmd.exec).to eq(ret: :ok)
    expect(daemon).to have_received(:update_all)
  end
end
