# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/remote_control'
require 'nodectld/remote_commands/base'
require 'nodectld/remote_commands/set'

RSpec.describe NodeCtld::RemoteCommands::Set do
  it 'patches each provided config change' do
    $CFG = runtime_cfg
    ret = described_class.new(
      {
        resource: 'config',
        config: [
          { vpsadmin: { queues: { vps: { threads: 4 } } } },
          { console: { enable: false } }
        ]
      },
      nil
    ).exec

    expect(ret).to eq(ret: :ok)
    expect($CFG.get(:vpsadmin, :queues, :vps, :threads)).to eq(4)
    expect($CFG.get(:console, :enable)).to be(false)
  end

  it 'raises a system command failure for unknown resources' do
    expect do
      described_class.new({ resource: 'unknown' }, nil).exec
    end.to raise_error(NodeCtld::SystemCommandFailed) { |err|
      expect(err.output).to eq('Unknown resource unknown')
    }
  end
end
