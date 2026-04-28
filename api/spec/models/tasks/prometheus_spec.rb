# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe VpsAdmin::API::Tasks::Prometheus do
  subject(:task) do
    allow(Prometheus::Client).to receive(:registry).and_return(registry)
    described_class.new
  end

  around do |example|
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  let(:registry) { Prometheus::Client::Registry.new }

  def create_export_host_owner_mismatch!(dataset_in_pool:)
    export, _netif, ip = create_export_for_dataset!(
      dataset_in_pool: dataset_in_pool,
      user: SpecSeed.user
    )
    ip.update_column(:user_id, SpecSeed.other_user.id)
    ExportHost.create!(
      export: export,
      ip_address: ip,
      rw: true,
      sync: true,
      subtree_check: false,
      root_squash: false
    )
  end

  def fake_dns_message(answer)
    message = Object.new
    dns_answer = Struct.new(:rdata).new(answer)
    allow(message).to receive(:authority).and_return([])
    allow(message).to receive(:each_answer).and_yield(dns_answer)
    message
  end

  describe '#export_base' do
    it 'writes representative base metrics to the configured file atomically' do
      export_file = File.join(Dir.mktmpdir, 'base.prom')
      stub_const("#{described_class}::EXPORT_FILE", export_file)
      fixture = build_active_dataset_expansion_fixture(user: SpecSeed.user)
      chain = build_active_chain!(state: :fatal)
      export_host = create_export_host_owner_mismatch!(dataset_in_pool: fixture.fetch(:dataset_in_pool))
      allow(File).to receive(:write).and_call_original
      allow(File).to receive(:rename).and_call_original

      task.export_base

      text = File.read(export_file)
      expect(File).to have_received(:write).with("#{export_file}.new", include('vpsadmin_user_count'))
      expect(File).to have_received(:rename).with("#{export_file}.new", export_file)
      expect(File.exist?("#{export_file}.new")).to be(false)
      expect(text).to include('vpsadmin_user_count')
      expect(text).to include('vpsadmin_vps_count')
      expect(text).to include('vpsadmin_transaction_chain_count')
      expect(text).to include('vpsadmin_transaction_chain_fatal')
      expect(text).to include('vpsadmin_dataset_expansion_count')
      expect(text).to include('vpsadmin_export_host_ip_owner_mismatch')
      expect(text).to include(%(chain_id="#{chain.id}"))
      expect(text).to include(%(dataset_name="#{fixture.fetch(:dataset).full_name}"))
      expect(text).to include(%(ip_address_id="#{export_host.ip_address_id}"))
    end
  end

  describe '#export_dns_records' do
    it 'exports answer-error metrics for matching and mismatching record answers' do
      export_file = File.join(Dir.mktmpdir, 'dns.prom')
      stub_const("#{described_class}::EXPORT_FILE", export_file)
      zone = create_dns_zone!(name: "prom-#{SecureRandom.hex(4)}.example.test.")
      server = create_dns_server!(node: SpecSeed.node, name: "ns-prom-#{SecureRandom.hex(4)}")
      create_dns_server_zone!(dns_zone: zone, dns_server: server)
      ok = create_dns_record!(dns_zone: zone, name: 'ok', record_type: 'A', content: '192.0.2.10')
      bad = create_dns_record!(dns_zone: zone, name: 'bad', record_type: 'A', content: '192.0.2.11')
      resolver = instance_double(Dnsruby::Resolver)
      allow(Dnsruby::Resolver).to receive(:new).and_return(resolver)
      allow(resolver).to receive(:nameserver=).with(server.ipv4_addr)
      allow(resolver).to receive(:query) do |name, _type, _klass|
        fake_dns_message(name.start_with?('ok.') ? '192.0.2.10' : '198.51.100.10')
      end

      task.export_dns_records

      text = File.read(export_file)
      expect(text).to match(
        /vpsadmin_dns_record_answer_error\{[^}]*record_id="#{ok.id}"[^}]*record_name="ok"[^}]*\} 0\.0/
      )
      expect(text).to match(
        /vpsadmin_dns_record_answer_error\{[^}]*record_id="#{bad.id}"[^}]*record_name="bad"[^}]*\} 1\.0/
      )
      expect(text).to include(%(dns_zone="#{zone.name}"))
      expect(text).to include(%(dns_server="#{server.name}"))
      expect(text).to include('record_type="A"')
    end
  end

  describe '#record_matches_answer?' do
    it 'matches TLSA answers even when Dnsruby inserts spaces into hex data' do
      association_data = 'A' * 64
      record = DnsRecord.new(
        record_type: 'TLSA',
        content: "3 1 1 #{association_data}"
      )
      rdata = Dnsruby::RR::IN::TLSA.new([3, 1, 1, [association_data].pack('H*')]).rdata

      expect(task.send(:record_matches_answer?, record, rdata)).to be(true)
    end

    it 'rejects TLSA answers with different association data' do
      association_data = 'A' * 64
      record = DnsRecord.new(
        record_type: 'TLSA',
        content: "3 1 1 #{association_data}"
      )
      rdata = Dnsruby::RR::IN::TLSA.new([3, 1, 1, ["#{'a' * 63}b"].pack('H*')]).rdata

      expect(task.send(:record_matches_answer?, record, rdata)).to be(false)
    end

    it 'matches SSHFP answers when the fingerprint differs only by hex case' do
      fingerprint = 'AABBCCDDEEFF00112233445566778899AABBCCDDEEFF00112233445566778899'
      record = DnsRecord.new(
        record_type: 'SSHFP',
        content: "4 2 #{fingerprint}"
      )
      rdata = Dnsruby::RR::SSHFP.new([4, 2, [fingerprint].pack('H*')]).rdata

      expect(task.send(:record_matches_answer?, record, rdata)).to be(true)
    end

    it 'rejects SSHFP answers with a different fingerprint' do
      fingerprint = 'AABBCCDDEEFF00112233445566778899AABBCCDDEEFF00112233445566778899'
      record = DnsRecord.new(
        record_type: 'SSHFP',
        content: "4 2 #{fingerprint}"
      )
      rdata = Dnsruby::RR::SSHFP.new([4, 2, ["#{'a' * 63}b"].pack('H*')]).rdata

      expect(task.send(:record_matches_answer?, record, rdata)).to be(false)
    end
  end
end
