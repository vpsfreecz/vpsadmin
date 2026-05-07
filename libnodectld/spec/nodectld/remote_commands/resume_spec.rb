# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/remote_control'
require 'nodectld/remote_commands/base'
require 'nodectld/remote_commands/resume'

RSpec.describe NodeCtld::RemoteCommands::Resume do
  it 'resumes the daemon' do
    daemon = instance_spy(NodeCtldSpec::FakeDaemon)

    expect(described_class.new({}, daemon).exec).to eq(ret: :ok)
    expect(daemon).to have_received(:resume)
  end
end
