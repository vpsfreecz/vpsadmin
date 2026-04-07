# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/vps/reinstall'

RSpec.describe NodeCtld::Commands::Vps::Reinstall do
  let(:driver) { build_storage_driver }
  let(:cmd) do
    described_class.new(
      driver,
      'vps_id' => 101,
      'pool_name' => 'tank',
      'distribution' => 'specos',
      'version' => '1',
      'arch' => 'x86_64',
      'vendor' => 'spec',
      'variant' => 'base'
    )
  end

  it 'reinstalls the VPS and clears container mounts afterwards' do
    allow(cmd).to receive_messages(osctl: { ret: :ok }, osctl_pool: { ret: :ok })

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(
      %i[ct reinstall],
      101,
      distribution: 'specos',
      version: '1',
      arch: 'x86_64',
      vendor: 'spec',
      variant: 'base'
    )
    expect(cmd).to have_received(:osctl_pool).with(
      'tank',
      %i[ct mounts clear],
      101
    )
  end
end
