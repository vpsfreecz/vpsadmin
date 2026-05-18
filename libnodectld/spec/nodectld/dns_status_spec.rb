# frozen_string_literal: true

require 'spec_helper'
require 'rexml/document'
require 'nodectld/dns_config'
require 'nodectld/dns_status'

RSpec.describe NodeCtld::DnsStatus do
  def bind_response(body, code: '200', message: 'OK')
    instance_double(Net::HTTPResponse, code: code, message: message, body: body)
  end

  def zone(name, dnssec_enabled)
    Struct.new(:name, :dnssec_enabled).new(name, dnssec_enabled)
  end

  def dns_config(zones)
    Struct.new(:zones) do
      def any_zones?
        zones.any?
      end

      def [](name)
        zones[name] ||
          zones.find { |zone_name, _zone| canonical(zone_name) == canonical(name) }&.last
      end

      def canonical(name)
        normalized = name.end_with?('.') ? name : "#{name}."
        normalized.downcase
      end
    end.new(zones)
  end

  before do
    stub_node_bunny
  end

  it 'does not publish when no zones are configured' do
    status = described_class.new

    allow(NodeCtld::DnsConfig).to receive(:instance).and_return(dns_config({}))
    allow(NodeCtld::NodeBunny).to receive(:publish_drop)

    expect(status.send(:check_status)).to be_nil
    expect(NodeCtld::NodeBunny).not_to have_received(:publish_drop)
  end

  it 'publishes parsed primary DNSSEC and secondary timing state' do
    Dir.mktmpdir do |dir|
      $CFG = runtime_cfg(dns_server: { bind_workdir: dir })
      key_path = File.join(dir, 'Kexample.test.+013+12345.key')
      File.write(key_path, "example.test. IN DNSKEY 257 3 13 ABCD EFG\n")
      zones = {
        'example.test.' => zone('example.test.', true),
        'secondary.test.' => zone('secondary.test.', false)
      }
      xml = <<~XML
        <statistics>
          <views>
            <view>
              <zones>
                <zone name="example.test.">
                  <type>primary</type>
                  <serial>123</serial>
                  <loaded>2026-01-01T00:00:00Z</loaded>
                </zone>
                <zone name="secondary.test">
                  <type>secondary</type>
                  <serial>-</serial>
                  <loaded>2026-01-01T00:00:00Z</loaded>
                  <expires>2026-01-02T00:00:00Z</expires>
                  <refresh>2026-01-01T01:00:00Z</refresh>
                </zone>
              </zones>
            </view>
          </views>
        </statistics>
      XML
      published = []
      status = described_class.new

      allow(NodeCtld::DnsConfig).to receive(:instance).and_return(dns_config(zones))
      allow(Net::HTTP).to receive(:get_response).and_return(bind_response(xml))
      allow(NodeCtld::NodeBunny).to receive(:publish_drop) do |_exchange, payload, **_opts|
        published << JSON.parse(payload)
      end

      status.send(:check_status)

      expect(published.length).to eq(1)
      expect(published.first.fetch('zones')).to contain_exactly(
        include(
          'name' => 'example.test.',
          'type' => 'primary',
          'serial' => 123,
          'dnskeys' => [
            {
              'keyid' => 12_345,
              'algorithm' => 13,
              'pubkey' => 'ABCDEFG'
            }
          ]
        ),
        include(
          'name' => 'secondary.test.',
          'type' => 'secondary',
          'serial' => nil,
          'expires' => Time.parse('2026-01-02T00:00:00Z').to_i,
          'refresh' => Time.parse('2026-01-01T01:00:00Z').to_i
        )
      )
    end
  end

  it 'publishes the configured zone name when BIND reports a different canonical form' do
    zones = {
      'Example.TEST.' => zone('Example.TEST.', false)
    }
    xml = <<~XML
      <statistics>
        <views>
          <view>
            <zones>
              <zone name="example.test">
                <type>primary</type>
                <serial>488</serial>
                <loaded>2026-01-01T00:00:00Z</loaded>
              </zone>
            </zones>
          </view>
        </views>
      </statistics>
    XML
    published = []
    status = described_class.new

    allow(NodeCtld::DnsConfig).to receive(:instance).and_return(dns_config(zones))
    allow(Net::HTTP).to receive(:get_response).and_return(bind_response(xml))
    allow(NodeCtld::NodeBunny).to receive(:publish_drop) do |_exchange, payload, **_opts|
      published << JSON.parse(payload)
    end

    status.send(:check_status)

    expect(published.length).to eq(1)
    expect(published.first.fetch('zones')).to contain_exactly(
      include(
        'name' => 'Example.TEST.',
        'serial' => 488
      )
    )
  end

  it 'skips malformed zone statuses without dropping valid zones' do
    zones = {
      'ok.test.' => zone('ok.test.', false),
      'bad.test.' => zone('bad.test.', false)
    }
    xml = <<~XML
      <statistics>
        <views>
          <view>
            <zones>
              <zone name="bad.test">
                <type>primary</type>
                <serial>123</serial>
                <loaded>not-a-time</loaded>
              </zone>
              <zone name="ok.test">
                <type>primary</type>
                <serial>124</serial>
                <loaded>2026-01-01T00:00:00Z</loaded>
              </zone>
            </zones>
          </view>
        </views>
      </statistics>
    XML
    published = []
    status = described_class.new

    allow(NodeCtld::DnsConfig).to receive(:instance).and_return(dns_config(zones))
    allow(Net::HTTP).to receive(:get_response).and_return(bind_response(xml))
    allow(status).to receive(:log)
    allow(NodeCtld::NodeBunny).to receive(:publish_drop) do |_exchange, payload, **_opts|
      published << JSON.parse(payload)
    end

    status.send(:check_status)

    expect(status).to have_received(:log).with(:warn, /bad\.test/)
    expect(published.length).to eq(1)
    expect(published.first.fetch('zones')).to contain_exactly(
      include(
        'name' => 'ok.test.',
        'serial' => 124,
        'loaded' => Time.parse('2026-01-01T00:00:00Z').to_i
      )
    )
  end

  it 'logs and returns nil on HTTP failure' do
    status = described_class.new

    allow(NodeCtld::DnsConfig).to receive(:instance).and_return(
      dns_config('example.test.' => zone('example.test.', false))
    )
    allow(Net::HTTP).to receive(:get_response).and_return(bind_response('', code: '500', message: 'Nope'))
    allow(status).to receive(:log)
    allow(NodeCtld::NodeBunny).to receive(:publish_drop)

    expect(status.send(:check_status)).to be_nil
    expect(status).to have_received(:log).with(:warn, /Failed to fetch BIND stats/)
    expect(NodeCtld::NodeBunny).not_to have_received(:publish_drop)
  end

  it 'logs and returns nil on XML parse failure' do
    status = described_class.new

    allow(NodeCtld::DnsConfig).to receive(:instance).and_return(
      dns_config('example.test.' => zone('example.test.', false))
    )
    allow(Net::HTTP).to receive(:get_response).and_return(bind_response('<bad'))
    allow(status).to receive(:log)
    allow(NodeCtld::NodeBunny).to receive(:publish_drop)

    expect(status.send(:check_status)).to be_nil
    expect(status).to have_received(:log).with(:warn, /Failed to parse XML/)
    expect(NodeCtld::NodeBunny).not_to have_received(:publish_drop)
  end
end
