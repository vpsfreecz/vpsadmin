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
