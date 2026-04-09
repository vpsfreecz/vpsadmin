# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/export/set'
require 'nodectld/nfs_server'

RSpec.describe NodeCtld::Commands::Export::Set do
  let(:driver) { build_storage_driver }
  let(:server) { instance_spy(NodeCtld::NfsServer) }
  let(:cmd) do
    described_class.new(
      driver,
      'export_id' => 42,
      'new' => { 'threads' => 16 },
      'original' => { 'threads' => 8 }
    )
  end

  before do
    allow(NodeCtld::NfsServer).to receive(:new).with(42, nil).and_return(server)
    allow(server).to receive(:set!).with(16).and_return(ret: :ok)
    allow(server).to receive(:set!).with(8).and_return(ret: :ok)
  end

  it 'applies the new thread count and restores the original one on rollback' do
    expect(cmd.exec).to eq(ret: :ok)
    expect(server).to have_received(:set!).with(16)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(server).to have_received(:set!).with(8)
  end
end
