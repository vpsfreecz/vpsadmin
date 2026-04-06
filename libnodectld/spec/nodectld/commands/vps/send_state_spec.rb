# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/vps/send_state'

RSpec.describe NodeCtld::Commands::Vps::SendState do
  let(:driver) { build_storage_driver }
  let(:cmd) do
    described_class.new(
      driver,
      'vps_id' => 101,
      'clone' => true,
      'start' => true,
      'restart' => true,
      'consistent' => false
    )
  end

  it 'forwards send-state options to osctl' do
    allow(cmd).to receive(:osctl).and_return(ret: :ok)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(
      %i[ct send state],
      101,
      {
        clone: true,
        start: true,
        restart: true,
        consistent: false
      },
      {},
      {}
    )
  end

  it 'has a no-op rollback' do
    expect(cmd.rollback).to eq(ret: :ok)
  end
end
