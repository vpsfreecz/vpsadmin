# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/dataset/remove_clone'

RSpec.describe NodeCtld::Commands::Dataset::RemoveClone do
  let(:driver) { build_storage_driver }

  it 'sets canmount=off before destroying the mounted clone path' do
    cmd = described_class.new(
      driver,
      'pool_fs' => 'tank/backup',
      'clone_name' => '42.snapshot'
    )
    calls = []

    allow(cmd).to receive(:zfs) do |*args|
      calls << args
      { ret: :ok }
    end

    expect(cmd.exec).to eq(ret: :ok)
    expect(calls).to eq([
                          [:set, 'canmount=off', 'tank/backup/vpsadmin/mount/42.snapshot'],
                          [:destroy, nil, 'tank/backup/vpsadmin/mount/42.snapshot']
                        ])
  end
end
