# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/dns_server_zone'

RSpec.describe NodeCtld::DnsServerZone do
  before do
    allow(FileUtils).to receive(:chown)
  end

  around do |example|
    Dir.mktmpdir('dns-server-zone-spec') do |dir|
      $CFG = NodeCtldSpec::FakeCfg.new(
        dns_server: {
          db_template: File.join(dir, '%{name}.json'),
          zone_template: File.join(dir, '%{name}.zone')
        }
      )

      example.run
    end
  end

  let(:zone) do
    described_class.new(
      name: 'example.test.',
      source: 'internal_source',
      type: 'primary_type',
      default_ttl: 3600,
      nameservers: ['ns1.example.test', 'ns2.example.test.'],
      serial: 2_026_040_300,
      email: 'hostmaster@example.test',
      primaries: [],
      secondaries: [],
      dnssec_enabled: false,
      enabled: true,
      load_db: false
    )
  end

  def build_record(id:, name:, type:, content:, ttl: 3600, priority: nil)
    {
      'id' => id,
      'name' => name,
      'type' => type,
      'content' => content,
      'ttl' => ttl,
      'priority' => priority
    }
  end

  def zone_text
    File.read(zone.zone_file)
  end

  it 'writes TLSA records unchanged into the zone file' do
    content = "3 1 1 #{'A' * 64}"
    record_re = /^_443\._tcp\.www\s+3600\s+IN\s+TLSA\s+#{Regexp.escape(content)}$/

    zone.replace_all_records([
                               build_record(id: 101, name: '_443._tcp.www', type: 'TLSA', content: content)
                             ])

    expect(zone_text).to include('$ORIGIN example.test.')
    expect(zone_text.lines.any? { |line| line.match?(record_re) }).to be(true)
  end

  it 'updates and deletes TLSA records without altering content' do
    original = build_record(
      id: 101,
      name: '_443._tcp.www',
      type: 'TLSA',
      content: "3 1 1 #{'A' * 64}"
    )
    updated = original.merge('content' => "3 1 0 #{'AB' * 8}")
    record_re = /^_443\._tcp\.www\s+3600\s+IN\s+TLSA\s+#{Regexp.escape(updated['content'])}$/

    zone.replace_all_records([original])
    zone.update_record(updated)

    expect(zone_text.lines.any? { |line| line.match?(record_re) }).to be(true)

    zone.delete_record(updated)

    expect(zone_text).not_to include(updated['content'])
    expect(zone_text.lines.any? { |line| line.match?(/^\S+\s+\d+\s+IN\s+TLSA\b/) }).to be(false)
  end
end
