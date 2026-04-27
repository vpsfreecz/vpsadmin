# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/shaper/root_change'

RSpec.describe NodeCtld::Commands::Shaper::RootChange do
  let(:driver) { build_storage_driver }
  let(:cmd) do
    described_class.new(
      driver,
      'max_tx' => 1000,
      'max_rx' => 2000,
      'original' => {
        'max_tx' => 500,
        'max_rx' => 750
      }
    )
  end

  before do
    stub_const('NodeCtld::Shaper', Class.new)
    allow(NodeCtld::Shaper).to receive(:update_root)
  end

  it 'is a no-op when shaper support is disabled' do
    allow($CFG).to receive(:get).with(:shaper, :enable).and_return(false)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd.rollback).to eq(ret: :ok)
    expect(NodeCtld::Shaper).not_to have_received(:update_root)
  end

  it 'updates root limits and restores the original values on rollback' do
    allow($CFG).to receive(:get).with(:shaper, :enable).and_return(true)

    expect(cmd.exec).to eq(ret: :ok)
    expect(NodeCtld::Shaper).to have_received(:update_root).with(1000, 2000)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(NodeCtld::Shaper).to have_received(:update_root).with(500, 750)
  end
end
