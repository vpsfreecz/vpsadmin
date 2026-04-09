# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/export/enable'
require 'nodectld/nfs_server'

RSpec.describe NodeCtld::Commands::Export::Enable do
  let(:driver) { build_storage_driver }
  let(:server) { instance_spy(NodeCtld::NfsServer) }
  let(:cmd) { described_class.new(driver, 'export_id' => 42) }

  before do
    allow(NodeCtld::NfsServer).to receive(:new).with(42, nil).and_return(server)
    # `receive_messages` triggers a load error in this spec environment.
    # rubocop:disable RSpec/ReceiveMessages
    allow(server).to receive(:start!).and_return(ret: :ok)
    allow(server).to receive(:stop!).and_return(ret: :ok)
    # rubocop:enable RSpec/ReceiveMessages
  end

  it 'starts the export and stops it on rollback' do
    expect(cmd.exec).to eq(ret: :ok)
    expect(server).to have_received(:start!)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(server).to have_received(:stop!)
  end
end
