# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/vps/unmanage_dns_resolver'

RSpec.describe NodeCtld::Commands::Vps::UnmanageDnsResolver do
  let(:driver) { build_vps_driver }
  let(:cmd) do
    described_class.new(
      driver,
      'vps_id' => 101,
      'original' => %w[1.1.1.1 8.8.8.8]
    )
  end

  before do
    allow(cmd).to receive(:osctl).and_return(ret: :ok)
  end

  it 'unsets the managed resolver on exec' do
    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(%i[ct unset dns-resolver], 101)
  end

  it 'restores the original resolver list on rollback' do
    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(
      %i[ct set dns-resolver],
      [101, '1.1.1.1', '8.8.8.8']
    )
  end
end
