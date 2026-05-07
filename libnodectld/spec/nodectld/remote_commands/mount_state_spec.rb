# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/remote_control'
require 'nodectld/remote_commands/base'
require 'nodectld/remote_commands/mount_state'
require 'nodectld/mount_reporter'

RSpec.describe NodeCtld::RemoteCommands::MountState do
  it 'reports the mount state with integer ids and a symbol state' do
    allow(NodeCtld::MountReporter).to receive(:report)

    ret = described_class.new(
      { vps_id: '101', mount_id: '202', state: 'mounted' },
      nil
    ).exec

    expect(ret).to eq(ret: :ok)
    expect(NodeCtld::MountReporter).to have_received(:report).with(101, 202, :mounted)
  end
end
