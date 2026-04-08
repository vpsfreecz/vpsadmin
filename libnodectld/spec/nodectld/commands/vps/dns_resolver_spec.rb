# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/vps/dns_resolver'

RSpec.describe NodeCtld::Commands::Vps::DnsResolver do
  let(:driver) { build_vps_driver }

  it 'sets the requested resolver list on exec' do
    cmd = described_class.new(
      driver,
      'vps_id' => 101,
      'nameserver' => %w[1.1.1.1 8.8.8.8],
      'original' => %w[9.9.9.9]
    )

    allow(cmd).to receive(:osctl).and_return(ret: :ok)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(
      %i[ct set dns-resolver],
      [101, '1.1.1.1', '8.8.8.8']
    )
  end

  it 'restores the original resolver list on rollback' do
    cmd = described_class.new(
      driver,
      'vps_id' => 101,
      'nameserver' => %w[1.1.1.1 8.8.8.8],
      'original' => %w[9.9.9.9]
    )

    allow(cmd).to receive(:osctl).and_return(ret: :ok)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(
      %i[ct set dns-resolver],
      [101, '9.9.9.9']
    )
  end

  it 'unsets the resolver when there is no original value to restore' do
    cmd = described_class.new(
      driver,
      'vps_id' => 101,
      'nameserver' => %w[1.1.1.1 8.8.8.8],
      'original' => nil
    )

    allow(cmd).to receive(:osctl).and_return(ret: :ok)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:osctl).with(%i[ct unset dns-resolver], 101)
  end
end
