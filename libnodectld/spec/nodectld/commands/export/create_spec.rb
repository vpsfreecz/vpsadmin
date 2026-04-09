# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/export/create'
require 'nodectld/nfs_server'

RSpec.describe NodeCtld::Commands::Export::Create do
  let(:driver) { build_storage_driver }
  let(:server) { instance_spy(NodeCtld::NfsServer) }
  let(:cmd) do
    described_class.new(
      driver,
      'export_id' => 42,
      'address' => '192.0.2.10',
      'threads' => 16
    )
  end

  before do
    allow(NodeCtld::NfsServer).to receive(:new).with(42, '192.0.2.10').and_return(server)
    allow(server).to receive(:create!).with(threads: 16).and_return(ret: :ok)
    allow(server).to receive(:destroy).and_return(ret: :ok)
  end

  it 'creates the runtime export with the requested thread count and destroys it on rollback' do
    expect(cmd.exec).to eq(ret: :ok)
    expect(server).to have_received(:create!).with(threads: 16)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(server).to have_received(:destroy)
  end
end
