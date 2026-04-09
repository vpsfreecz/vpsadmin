# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/dns_server_zone/update_records'
require 'nodectld/dns_server_zone'

RSpec.describe NodeCtld::Commands::DnsServerZone::UpdateRecords do
  let(:driver) { build_storage_driver }
  let(:zone) { instance_spy(NodeCtld::DnsServerZone) }
  let(:records) do
    [
      {
        'new' => {
          'id' => 101,
          'name' => 'www',
          'type' => 'A',
          'content' => '192.0.2.20',
          'ttl' => 3600
        },
        'original' => {
          'id' => 101,
          'name' => 'www',
          'type' => 'A',
          'content' => '192.0.2.10',
          'ttl' => 3600
        }
      }
    ]
  end
  let(:cmd) { described_class.new(driver, 'records' => records) }

  before do
    allow(cmd).to receive(:get_dns_server_zone).and_return(zone)
    allow(zone).to receive(:update_record)
  end

  it 'applies updated records and restores the originals on rollback' do
    expect(cmd.exec).to eq(ret: :ok)
    expect(zone).to have_received(:update_record).with(records.first.fetch('new'))

    expect(cmd.rollback).to eq(ret: :ok)
    expect(zone).to have_received(:update_record).with(records.first.fetch('original'))
  end
end
