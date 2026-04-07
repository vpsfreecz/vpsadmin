# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/vps/destroy'
require 'nodectld/net_accounting'

RSpec.describe NodeCtld::Commands::Vps::Destroy do
  let(:driver) { build_vps_driver }
  let(:cmd) do
    described_class.new(
      driver,
      'vps_id' => 101
    )
  end

  it 'deletes the container and unregisters network accounting' do
    allow(cmd).to receive(:osctl).and_return(ret: :ok)
    allow(NodeCtld::NetAccounting).to receive(:remove_vps)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(%i[ct del], 101)
    expect(NodeCtld::NetAccounting).to have_received(:remove_vps).with(101)
  end
end
