# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/dns_server_zone/create'
require 'nodectld/dns_config'
require 'nodectld/dns_server_zone'

RSpec.describe NodeCtld::Commands::DnsServerZone::Create do
  let(:driver) { build_storage_driver }
  let(:zone) { instance_spy(NodeCtld::DnsServerZone) }
  let(:dns_config) { instance_spy(NodeCtld::DnsConfig) }
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
  let(:cmd) do
    described_class.new(
      driver,
      'name' => 'example.test',
      'source' => 'internal_source',
      'type' => 'primary_type',
      'records' => records
    )
  end

  before do
    allow(cmd).to receive(:get_dns_server_zone).and_return(zone)
    allow(NodeCtld::DnsConfig).to receive(:instance).and_return(dns_config)
    allow(zone).to receive(:replace_all_records)
    allow(zone).to receive(:destroy)
    allow(dns_config).to receive(:add_zone)
    allow(dns_config).to receive(:remove_zone)
  end

  it 'replaces all records and registers the zone in dns config' do
    expect(cmd.exec).to eq(ret: :ok)
    expect(zone).to have_received(:replace_all_records).with(records)
    expect(dns_config).to have_received(:add_zone).with(zone)
  end

  it 'removes the zone from dns config and destroys it on rollback' do
    expect(cmd.rollback).to eq(ret: :ok)
    expect(dns_config).to have_received(:remove_zone).with(zone)
    expect(zone).to have_received(:destroy)
  end
end
