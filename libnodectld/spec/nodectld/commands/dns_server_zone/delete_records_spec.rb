# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/dns_server_zone/delete_records'
require 'nodectld/dns_server_zone'

RSpec.describe NodeCtld::Commands::DnsServerZone::DeleteRecords do
  let(:driver) { build_storage_driver }
  let(:zone) { instance_spy(NodeCtld::DnsServerZone) }
  let(:records) do
    [
      {
        'id' => 101,
        'name' => 'www',
        'type' => 'A',
        'content' => '192.0.2.10',
        'ttl' => 3600
      }
    ]
  end
  let(:cmd) { described_class.new(driver, 'records' => records) }

  before do
    allow(cmd).to receive(:get_dns_server_zone).and_return(zone)
    allow(zone).to receive(:delete_record)
    allow(zone).to receive(:create_record)
  end

  it 'deletes the requested records and recreates them on rollback' do
    expect(cmd.exec).to eq(ret: :ok)
    expect(zone).to have_received(:delete_record).with(records.first)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(zone).to have_received(:create_record).with(records.first)
  end
end
