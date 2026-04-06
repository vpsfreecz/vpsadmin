# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/vps/send_rollback_config'

RSpec.describe NodeCtld::Commands::Vps::SendRollbackConfig do
  let(:driver) { build_storage_driver }
  let(:cmd) do
    described_class.new(
      driver,
      'vps_id' => 101
    )
  end

  it 'returns ok from exec' do
    expect(cmd.exec).to eq(ret: :ok)
  end

  it 'destroys the destination config on rollback' do
    allow(cmd).to receive(:osctl).and_return(ret: :ok)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(
      %i[ct del],
      101,
      force: true
    )
  end
end
