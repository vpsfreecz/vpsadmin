# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/dns_server_zone/add_servers'
require 'nodectld/dns_config'
require 'nodectld/dns_server_zone'

RSpec.describe NodeCtld::Commands::DnsServerZone::AddServers do
  let(:driver) { build_storage_driver }
  let(:dns_config) { instance_spy(NodeCtld::DnsConfig) }
  let(:zone) do
    instance_double(
      NodeCtld::DnsServerZone,
      nameservers: zone_nameservers,
      primaries: zone_primaries,
      secondaries: zone_secondaries,
      save: nil
    )
  end
  let(:cmd) do
    described_class.new(
      driver,
      'name' => 'example.test',
      'source' => 'internal_source',
      'type' => 'primary_type',
      'nameservers' => ['ns2.example.test'],
      'primaries' => [{ 'ip_addr' => '192.0.2.10' }],
      'secondaries' => [{ 'ip_addr' => '192.0.2.20' }]
    )
  end

  def zone_nameservers
    @zone_nameservers ||= ['ns1.example.test']
  end

  def zone_primaries
    @zone_primaries ||= [{ 'ip_addr' => '192.0.2.1' }]
  end

  def zone_secondaries
    @zone_secondaries ||= [{ 'ip_addr' => '192.0.2.2' }]
  end

  before do
    allow(NodeCtld::DnsServerZone).to receive(:new).with(
      name: 'example.test',
      source: 'internal_source',
      type: 'primary_type'
    ).and_return(zone)
    allow(NodeCtld::DnsConfig).to receive(:instance).and_return(dns_config)
    allow(dns_config).to receive(:update_zone)
  end

  it 'adds missing servers on exec and removes them on rollback' do
    expect(cmd.exec).to eq(ret: :ok)
    expect(zone_nameservers.sort).to eq(['ns1.example.test', 'ns2.example.test'])
    expect(zone_primaries.sort_by { |v| v.fetch('ip_addr') }).to eq(
      [
        { 'ip_addr' => '192.0.2.1' },
        { 'ip_addr' => '192.0.2.10' }
      ]
    )
    expect(zone_secondaries.sort_by { |v| v.fetch('ip_addr') }).to eq(
      [
        { 'ip_addr' => '192.0.2.2' },
        { 'ip_addr' => '192.0.2.20' }
      ]
    )
    expect(zone).to have_received(:save)
    expect(dns_config).to have_received(:update_zone).with(zone)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(zone_nameservers).to eq(['ns1.example.test'])
    expect(zone_primaries).to eq([{ 'ip_addr' => '192.0.2.1' }])
    expect(zone_secondaries).to eq([{ 'ip_addr' => '192.0.2.2' }])
  end
end
