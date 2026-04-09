# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/export/destroy'
require 'nodectld/nfs_server'

RSpec.describe NodeCtld::Commands::Export::Destroy do
  let(:driver) { build_storage_driver }
  let(:server) { instance_spy(NodeCtld::NfsServer) }
  let(:cmd) do
    described_class.new(
      driver,
      'export_id' => 42,
      'address' => '192.0.2.10'
    )
  end

  before do
    allow(NodeCtld::NfsServer).to receive(:new).with(42, '192.0.2.10').and_return(server)
    # `receive_messages` triggers a load error in this spec environment.
    # rubocop:disable RSpec/ReceiveMessages
    allow(server).to receive(:destroy!).and_return(ret: :ok)
    allow(server).to receive(:create!).and_return(ret: :ok)
    # rubocop:enable RSpec/ReceiveMessages
  end

  it 'destroys the runtime export and recreates it on rollback' do
    expect(cmd.exec).to eq(ret: :ok)
    expect(server).to have_received(:destroy!)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(server).to have_received(:create!)
  end
end
