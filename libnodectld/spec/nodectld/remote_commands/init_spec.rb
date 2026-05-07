# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/remote_control'
require 'nodectld/remote_commands/base'
require 'nodectld/remote_commands/init'
require 'nodectld/shaper'

RSpec.describe NodeCtld::RemoteCommands::Init do
  it 'initializes the shaper' do
    cmd = described_class.new({ resources: ['shaper'] }, nil)

    allow(cmd).to receive(:log)
    allow(NodeCtld::Shaper).to receive(:init)

    expect(cmd.exec).to eq(ret: :ok, output: { shaper: true })
    expect(NodeCtld::Shaper).to have_received(:init)
  end
end
