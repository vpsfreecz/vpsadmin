# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Tasks::Dns do
  let(:task) { described_class.new }

  def create_reverse_fixture!(server_count: 1)
    network = create_private_network!(location: SpecSeed.location, purpose: :vps)
    ip = create_ipv4_address_in_network!(network: network, location: SpecSeed.location)
    host_ip = ip.host_ip_addresses.take!
    zone = create_reverse_dns_zone!(
      name: "reverse-#{SecureRandom.hex(4)}.example.test.",
      network_address: network.address,
      network_prefix: network.prefix
    )
    record = create_dns_record!(
      dns_zone: zone,
      name: '25',
      record_type: 'PTR',
      content: 'host.example.test.'
    )
    host_ip.update!(reverse_dns_record: record)
    servers = server_count.times.map do |i|
      server = create_dns_server!(
        node: SpecSeed.node,
        name: "ns-rev-#{i}-#{SecureRandom.hex(4)}"
      )
      create_dns_server_zone!(dns_zone: zone, dns_server: server)
      server
    end

    { host_ip: host_ip, record: record, servers: servers }
  end

  def stub_ptr_query
    allow(VpsAdmin::API::DnsResolver).to receive(:open) do |addrs, &block|
      resolver = Object.new
      allow(resolver).to receive(:query_ptr) { |ip| yield(addrs, ip) }
      block.call(resolver)
    end
  end

  it 'counts correct PTR answers as successful' do
    fixture = create_reverse_fixture!
    stub_ptr_query { |_addrs, _ip| fixture.fetch(:record).content }

    expect { task.check_reverse_records }.to output(/1 records ok/).to_stdout
  end

  it 'retries ResolvError answers up to three times' do
    fixture = create_reverse_fixture!
    attempts = 0
    allow(task).to receive(:sleep)
    stub_ptr_query do |_addrs, _ip|
      attempts += 1
      raise Resolv::ResolvError if attempts < 3

      fixture.fetch(:record).content
    end

    task.check_reverse_records

    expect(attempts).to eq(3)
  end

  it 'reports DNS errors and exits non-zero when PTR cannot be resolved' do
    create_reverse_fixture!
    allow(task).to receive(:sleep)
    stub_ptr_query { |_addrs, _ip| raise Resolv::ResolvError }

    out, = capture_streams do
      expect { task.check_reverse_records }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end
    expect(out).to include("1 dns errors\n")
  end

  it 'reports incorrect PTR answers and exits non-zero' do
    create_reverse_fixture!
    stub_ptr_query { |_addrs, _ip| 'other.example.test.' }

    out, err = capture_streams do
      expect { task.check_reverse_records }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end
    expect(out).to include("1 records incorrect\n")
    expect(err).to include('returned "other.example.test."')
  end

  it 'filters DNS servers by SERVERS environment variable' do
    fixture = create_reverse_fixture!(server_count: 2)
    selected = fixture.fetch(:servers).last
    opened = []
    stub_ptr_query do |addrs, _ip|
      opened << addrs
      fixture.fetch(:record).content
    end

    with_env('SERVERS' => selected.name) { task.check_reverse_records }

    expect(opened).to eq([[selected.ipv4_addr]])
  end
end
