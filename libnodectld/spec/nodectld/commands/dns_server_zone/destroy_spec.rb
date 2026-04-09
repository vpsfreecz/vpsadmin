# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'nodectld/commands/base'
require 'nodectld/commands/dns_server_zone/destroy'
require 'nodectld/dns_config'
require 'nodectld/dns_server_zone'

RSpec.describe NodeCtld::Commands::DnsServerZone::Destroy do
  let(:driver) { build_vps_driver(id: 90_210) }
  let(:dns_config) { instance_spy(NodeCtld::DnsConfig) }
  let(:zone) do
    instance_double(
      NodeCtld::DnsServerZone,
      name: 'example.test',
      type: 'primary_type',
      destroy: nil,
      replace_all_records: nil
    )
  end
  let(:cmd) do
    described_class.new(
      driver,
      'name' => 'example.test',
      'records' => records
    )
  end

  def records
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

  def key_base
    'Kexample.test+013+12345'
  end

  around do |example|
    Dir.mktmpdir('dns-zone-destroy-spec') do |tmpdir|
      $CFG = NodeCtldSpec::FakeCfg.new(
        dns_server: {
          bind_workdir: tmpdir
        }
      )
      @tmpdir = tmpdir

      example.run
    end
  end

  before do
    %w[key private state].each do |ext|
      File.write(File.join(tmpdir, "#{key_base}.#{ext}"), "dnssec-#{ext}")
    end
    File.write(File.join(tmpdir, 'keep-me.txt'), 'untouched')

    allow(cmd).to receive(:get_dns_server_zone).and_return(zone)
    allow(NodeCtld::DnsConfig).to receive(:instance).and_return(dns_config)
    allow(dns_config).to receive(:remove_zone)
    allow(dns_config).to receive(:add_zone)
  end

  it 'removes dnssec keys on exec and restores them on rollback' do
    expect(cmd.exec).to eq(ret: :ok)

    expect(zone).to have_received(:destroy)
    expect(dns_config).to have_received(:remove_zone).with(zone)
    expect(Dir.children(tmpdir)).to include(
      "#{key_base}.key.destroyed-90210",
      "#{key_base}.private.destroyed-90210",
      "#{key_base}.state.destroyed-90210",
      'keep-me.txt'
    )

    expect(cmd.rollback).to eq(ret: :ok)

    expect(zone).to have_received(:replace_all_records).with(records)
    expect(dns_config).to have_received(:add_zone).with(zone)
    expect(Dir.children(tmpdir)).to include(
      "#{key_base}.key",
      "#{key_base}.private",
      "#{key_base}.state",
      'keep-me.txt'
    )
    expect(Dir.children(tmpdir)).not_to include(
      "#{key_base}.key.destroyed-90210",
      "#{key_base}.private.destroyed-90210",
      "#{key_base}.state.destroyed-90210"
    )
  end

  attr_reader :tmpdir
end
