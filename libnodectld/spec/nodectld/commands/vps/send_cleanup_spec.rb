# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/vps/send_cleanup'
require 'nodectld/net_accounting'

RSpec.describe NodeCtld::Commands::Vps::SendCleanup do
  let(:driver) { build_storage_driver }
  let(:cmd) do
    described_class.new(
      driver,
      'vps_id' => 101
    )
  end

  it 'cleans up send state and unregisters network accounting' do
    allow(cmd).to receive(:osctl).and_return(ret: :ok)
    allow(NodeCtld::NetAccounting).to receive(:remove_vps)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(%i[ct send cleanup], 101)
    expect(NodeCtld::NetAccounting).to have_received(:remove_vps).with(101)
  end
end
