# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/dns_server_zone/update'
require 'nodectld/dns_config'
require 'nodectld/dns_server_zone'

RSpec.describe NodeCtld::Commands::DnsServerZone::Update do
  let(:driver) { build_storage_driver }
  let(:zone) { instance_spy(NodeCtld::DnsServerZone) }
  let(:dns_config) { instance_spy(NodeCtld::DnsConfig) }
  let(:cmd) do
    described_class.new(
      driver,
      'name' => 'example.test',
      'source' => 'internal_source',
      'type' => 'primary_type',
      'new' => {
        'default_ttl' => 7200,
        'serial' => 2_026_040_800,
        'enabled' => false
      },
      'original' => {
        'default_ttl' => 3600,
        'serial' => 2_026_040_700,
        'enabled' => true
      }
    )
  end

  before do
    allow(zone).to receive(:save)
    allow(NodeCtld::DnsConfig).to receive(:instance).and_return(dns_config)
    allow(dns_config).to receive(:update_zone)
  end

  it 'saves attrs from the new hash and updates dns config' do
    allow(cmd).to receive(:get_dns_server_zone).with(
      default_ttl: 7200,
      serial: 2_026_040_800,
      enabled: false
    ).and_return(zone)

    expect(cmd.exec).to eq(ret: :ok)
    expect(cmd).to have_received(:get_dns_server_zone).with(
      default_ttl: 7200,
      serial: 2_026_040_800,
      enabled: false
    )
    expect(zone).to have_received(:save)
    expect(dns_config).to have_received(:update_zone).with(zone)
  end

  it 'restores attrs from the original hash on rollback' do
    allow(cmd).to receive(:get_dns_server_zone).with(
      default_ttl: 3600,
      serial: 2_026_040_700,
      enabled: true
    ).and_return(zone)

    expect(cmd.rollback).to eq(ret: :ok)
    expect(cmd).to have_received(:get_dns_server_zone).with(
      default_ttl: 3600,
      serial: 2_026_040_700,
      enabled: true
    )
    expect(zone).to have_received(:save)
    expect(dns_config).to have_received(:update_zone).with(zone)
  end
end
