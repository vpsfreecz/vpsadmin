# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'VpsAdmin::Supervisor::Node::DnsStatus' do
  def create_zone!(name:, user:, source: :internal_source)
    DnsZone.create!(
      name: name,
      user: user,
      zone_role: :forward_role,
      zone_source: source,
      dnssec_enabled: true,
      enabled: true,
      label: '',
      default_ttl: 3600,
      email: 'dns@example.test'
    )
  end

  describe '#process_status' do
    it 'continues with later zones after an update failure' do
      node = instance_double(Node, domain_name: 'dns-node.example.test')
      dns_status = VpsAdmin::Supervisor::Node::DnsStatus.new(nil, node)
      processed = []

      allow(dns_status).to receive(:warn)
      allow(dns_status).to receive(:update_zone) do |zone|
        processed << zone['name']
        raise ActiveRecord::RecordInvalid if zone['name'] == 'bad.example.test.'
      end

      dns_status.send(
        :process_status,
        {
          'zones' => [
            { 'name' => 'bad.example.test.' },
            { 'name' => 'ok.example.test.' }
          ]
        }
      )

      expect(processed).to eq(['bad.example.test.', 'ok.example.test.'])
      expect(dns_status).to have_received(:warn).with(/bad\.example\.test/)
    end
  end

  describe '#update_zone' do
    it 'updates status for zones with legacy invalid record sets' do
      dns_server = create_dns_server!(node: SpecSeed.node)
      zone = create_dns_zone!(
        name: 'spec-invalid-existing.example.test.',
        user: SpecSeed.user
      )
      server_zone = create_dns_server_zone!(
        dns_zone: zone,
        dns_server: dns_server,
        zone_type: :primary_type
      )

      create_dns_record!(
        dns_zone: zone,
        name: 'www',
        record_type: 'A',
        content: '198.51.100.10'
      )
      DnsRecord.new(
        dns_zone: zone,
        name: 'www',
        record_type: 'CNAME',
        content: "target.#{zone.name}"
      ).save!(validate: false)

      dns_status = VpsAdmin::Supervisor::Node::DnsStatus.new(nil, SpecSeed.node)
      dns_status.send(
        :update_zone,
        {
          'name' => zone.name,
          'time' => Time.utc(2026, 1, 1, 0, 5, 0).to_i,
          'serial' => 488,
          'loaded' => Time.utc(2026, 1, 1, 0, 0, 0).to_i,
          'dnskeys' => []
        }
      )

      server_zone.reload
      expect(server_zone.serial).to eq(488)
      expect(server_zone.last_check_at.to_i).to eq(Time.utc(2026, 1, 1, 0, 5, 0).to_i)
    end

    it 'stores refresh_at when BIND reports refresh without expires' do
      dns_server = create_dns_server!(node: SpecSeed.node)
      zone = create_dns_zone!(
        name: 'spec-refresh.example.test.',
        user: SpecSeed.user,
        source: :external_source
      )
      server_zone = create_dns_server_zone!(
        dns_zone: zone,
        dns_server: dns_server,
        zone_type: :secondary_type
      )
      refresh = Time.utc(2026, 1, 1, 1, 0, 0).to_i

      dns_status = VpsAdmin::Supervisor::Node::DnsStatus.new(nil, SpecSeed.node)
      dns_status.send(
        :update_zone,
        {
          'name' => zone.name,
          'time' => Time.utc(2026, 1, 1, 0, 5, 0).to_i,
          'serial' => 488,
          'loaded' => Time.utc(2026, 1, 1, 0, 0, 0).to_i,
          'refresh' => refresh
        }
      )

      server_zone.reload
      expect(server_zone.serial).to eq(488)
      expect(server_zone.refresh_at.to_i).to eq(refresh)
      expect(server_zone.expires_at).to be_nil
    end
  end

  describe '#update_dnskeys' do
    it 'updates an existing record when the dnskey public key changes' do
      zone = create_zone!(name: 'spec-sync.example.test.', user: SpecSeed.user)

      record = DnssecRecord.create!(
        dns_zone: zone,
        keyid: 12_345,
        dnskey_algorithm: 13,
        dnskey_pubkey: 'AAECAwQF +/==',
        ds_algorithm: 13,
        ds_digest_type: 2,
        ds_digest: 'stale-digest'
      )

      dns_status = VpsAdmin::Supervisor::Node::DnsStatus.new(nil, nil)

      dns_status.send(
        :update_dnskeys,
        zone,
        [
          {
            'keyid' => record.keyid,
            'algorithm' => 13,
            'pubkey' => 'AAECAwQF+/=='
          }
        ]
      )

      expect(zone.dnssec_records.count).to eq(1)

      record.reload
      expect(record.dnskey_pubkey).to eq('AAECAwQF+/==')
      expect(record.ds_algorithm).to eq(13)
      expect(record.ds_digest_type).to eq(2)
      expect(record.ds_digest).not_to eq('stale-digest')
    end
  end
end
