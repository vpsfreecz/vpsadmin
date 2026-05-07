# frozen_string_literal: true

require 'spec_helper'
require 'ipaddress'
require 'nodectld/route_list'

RSpec.describe NodeCtld::RouteList do
  def build_list(ip_v, route_entries)
    klass = Class.new(described_class) do
      attr_reader :command

      define_method(:syscmd) do |cmd|
        @command = cmd

        Object.new.tap do |ret|
          ret.define_singleton_method(:output) { route_entries.to_json }
        end
      end
    end

    klass.new(ip_v, 'spec')
  end

  it 'matches IPv4 host and network routes with the kernel route key format' do
    routes = build_list(4, [
                          { dst: '192.0.2.1', dev: 'eth0' },
                          { dst: '198.51.100.0/24', dev: 'eth1' }
                        ])

    expect(routes.command).to eq('ip -4 -json route list')
    expect(routes.include?(IPAddress.parse('192.0.2.1/32'))).to be(true)
    expect(routes.include?(IPAddress.parse('198.51.100.0/24'))).to be(true)
    expect(routes.include?(IPAddress.parse('203.0.113.0/24'))).to be(false)
  end

  it 'matches IPv6 host routes without the /128 suffix' do
    routes = build_list(6, [{ dst: '2001:db8::1', dev: 'eth0' }])

    expect(routes.command).to eq('ip -6 -json route list')
    expect(routes.include?(IPAddress.parse('2001:db8::1/128'))).to be(true)
    expect(routes.include?(IPAddress.parse('2001:db8::/64'))).to be(false)
  end
end
