# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/vps/unmanage_hostname'

RSpec.describe NodeCtld::Commands::Vps::UnmanageHostname do
  let(:driver) { build_vps_driver }
  let(:cmd) do
    described_class.new(
      driver,
      'vps_id' => 101,
      'hostname' => 'spec-vps'
    )
  end

  before do
    allow(cmd).to receive(:osctl).and_return(ret: :ok)
  end

  it 'unsets the managed hostname on exec' do
    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(%i[ct unset hostname], 101)
  end

  it 'restores the managed hostname on rollback' do
    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(%i[ct set hostname], [101, 'spec-vps'])
  end
end
