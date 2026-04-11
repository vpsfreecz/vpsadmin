# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/dns_config'
require 'nodectld/dns_server_zone'

RSpec.describe NodeCtld::DnsConfig do
  let(:tmpdir) { Dir.mktmpdir('dns-config-spec') }
  let(:config_root) { File.join(tmpdir, 'named.conf') }

  before do
    $CFG = NodeCtldSpec::FakeCfg.new(
      dns_server: {
        config_root: config_root,
        db_template: File.join(tmpdir, '%{name}-%{source}-%{type}.json'),
        zone_template: File.join(tmpdir, '%{name}-%{source}-%{type}.zone')
      }
    )

    Singleton.__init__(described_class)
  end

  after do
    Singleton.__init__(described_class)
    FileUtils.rm_rf(tmpdir)
  end

  def build_remote_server(ip_addr:, tsig_key: nil)
    {
      'ip_addr' => ip_addr,
      'tsig_key' => tsig_key
    }
  end

  def build_tsig_key(name:)
    {
      'name' => name,
      'algorithm' => 'hmac-sha256',
      'secret' => 'dGVzdA=='
    }
  end

  def build_zone(source:, primaries:, secondaries:)
    NodeCtld::DnsServerZone.new(
      name: 'example.test.',
      source: source,
      type: 'secondary_type',
      primaries: primaries,
      secondaries: secondaries,
      enabled: true,
      load_db: false
    )
  end

  def config_text
    File.read(config_root)
  end

  it 'renders also-notify for external secondary zones from peer secondaries only' do
    upstream = build_remote_server(
      ip_addr: '198.51.100.10',
      tsig_key: build_tsig_key(name: 'upstream-key.')
    )
    peer_secondary = build_remote_server(ip_addr: '198.51.100.20')
    zone = build_zone(
      source: 'external_source',
      primaries: [upstream, peer_secondary],
      secondaries: [peer_secondary]
    )

    described_class.instance.add_zone(zone)

    expect(config_text).to include('  type secondary;')
    expect(config_text).to include(
      '  primaries { 198.51.100.10 key upstream-key.; 198.51.100.20; };'
    )
    expect(config_text).to include('  notify yes;')
    expect(config_text).to include('  allow-transfer { 198.51.100.20; };')
    expect(config_text).to include('  also-notify { 198.51.100.20; };')
    expect(config_text).not_to include('  also-notify { 198.51.100.10')
  end

  it 'does not render also-notify when an external secondary has no peer secondaries' do
    zone = build_zone(
      source: 'external_source',
      primaries: [build_remote_server(ip_addr: '198.51.100.10')],
      secondaries: []
    )

    described_class.instance.add_zone(zone)

    expect(config_text).to include('  allow-transfer { none; };')
    expect(config_text).not_to include('also-notify')
  end

  it 'does not add external-only also-notify handling to internal secondaries' do
    zone = build_zone(
      source: 'internal_source',
      primaries: [build_remote_server(ip_addr: '198.51.100.10')],
      secondaries: [build_remote_server(ip_addr: '198.51.100.20')]
    )

    described_class.instance.add_zone(zone)

    expect(config_text).to include('  notify yes;')
    expect(config_text).to include('  allow-transfer { 198.51.100.20; };')
    expect(config_text).not_to include('also-notify')
  end
end
