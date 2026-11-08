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

  context 'with persisted tracking' do
    around do |example|
      Dir.mktmpdir('dns-zone-update-spec') do |dir|
        $CFG = NodeCtldSpec::FakeCfg.new(
          dns_server: {
            db_template: File.join(dir, '%{name}.json'),
            zone_template: File.join(dir, '%{name}.zone')
          }
        )
        example.run
      end
    end

    before do
      allow(NodeCtld::DnsConfig).to receive(:instance).and_return(dns_config)
      allow(FileUtils).to receive(:chown)
    end

    [true, false].each do |enabled|
      it "persists matching direction-specific tracking for #{enabled ? 'disable' : 'enable'} and rollback" do
        old_generation = enabled ? SecureRandom.uuid : nil
        new_generation = enabled ? nil : SecureRandom.uuid
        original = {
          'enabled' => enabled,
          'primary_transfer_generation' => old_generation,
          'primary_transfer_tracking_started_at' => enabled ? 100 : nil,
          'probe_source_addrs' => { 'ipv4' => '192.0.2.53', 'ipv6' => nil }
        }
        updated = {
          'enabled' => !enabled,
          'primary_transfer_generation' => new_generation,
          'primary_transfer_tracking_started_at' => enabled ? nil : 200,
          'probe_source_addrs' => { 'ipv4' => nil, 'ipv6' => '2001:db8::53' }
        }
        attrs = {
          'id' => 123,
          'name' => 'update.example.test.',
          'source' => 'external_source',
          'type' => 'secondary_type',
          'primaries' => [],
          'secondaries' => [],
          'primary_transfer_generation' => new_generation,
          'primary_transfer_tracking_started_at' => updated.fetch('primary_transfer_tracking_started_at'),
          'probe_source_addrs' => updated.fetch('probe_source_addrs'),
          'new' => updated,
          'original' => original
        }
        NodeCtld::DnsServerZone.new(
          id: 123, name: attrs.fetch('name'), source: 'external_source',
          type: 'secondary_type', primaries: [], secondaries: [], enabled:,
          primary_transfer_generation: old_generation,
          primary_transfer_tracking_started_at: original.fetch('primary_transfer_tracking_started_at'),
          probe_source_addrs: original.fetch('probe_source_addrs'),
          load_db: false
        ).save
        cmd = described_class.new(driver, attrs)

        expect(cmd.exec).to eq(ret: :ok)
        db_file = File.join($CFG.get(:dns_server, :db_template).sub('%{name}', attrs.fetch('name')))
        expect(JSON.parse(File.read(db_file))).to include(updated)
        expect(cmd.rollback).to eq(ret: :ok)
        expect(JSON.parse(File.read(db_file))).to include(original)
        expect(dns_config).to have_received(:update_zone).twice
      end
    end
  end
end
