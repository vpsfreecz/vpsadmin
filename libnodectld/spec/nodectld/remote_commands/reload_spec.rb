# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/remote_control'
require 'nodectld/remote_commands/base'
require 'nodectld/remote_commands/reload'

RSpec.describe NodeCtld::RemoteCommands::Reload do
  it 'reloads the config' do
    cmd = described_class.new({}, nil)

    allow(cmd).to receive(:log)
    allow($CFG).to receive(:reload)

    expect(cmd.exec).to eq(ret: :ok)
    expect($CFG).to have_received(:reload)
  end
end
