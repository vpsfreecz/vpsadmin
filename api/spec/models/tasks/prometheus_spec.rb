# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Tasks::Prometheus do
  subject(:task) do
    allow(Prometheus::Client).to receive(:registry).and_return(registry)
    described_class.new
  end

  let(:registry) { Prometheus::Client::Registry.new }

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
