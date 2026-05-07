# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/remote_control'
require 'nodectld/remote_commands/base'
require 'nodectld/remote_commands/ping'

RSpec.describe NodeCtld::RemoteCommands::Ping do
  it 'returns pong' do
    expect(described_class.new({}, nil).exec).to eq(
      ret: :ok,
      output: { pong: :pong }
    )
  end
end
