# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/dns_server/reload'

RSpec.describe NodeCtld::Commands::DnsServer::Reload do
  let(:driver) { build_storage_driver }

  it 'reloads a specific zone when requested' do
    cmd = described_class.new(driver, 'zone' => 'example.test')
    allow(cmd).to receive(:syscmd).and_return(ret: :ok)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:syscmd).with('rndc reload example.test')
  end

  it 'reloads the whole daemon when no zone is supplied and keeps rollback as a no-op' do
    cmd = described_class.new(driver, {})
    allow(cmd).to receive(:syscmd).and_return(ret: :ok)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:syscmd).with('rndc reload')
    expect(cmd.rollback).to eq(ret: :ok)
  end
end
