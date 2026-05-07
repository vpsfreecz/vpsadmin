# frozen_string_literal: true

require 'spec_helper'
require 'ipaddress'
require 'nodectld/vps_config'
require 'nodectld/vps_config/route'
require 'nodectld/route_check'

RSpec.describe NodeCtld::RouteCheck do
  def route(cidr)
    NodeCtld::VpsConfig::Route.new(IPAddress.parse(cidr), nil)
  end

  def build_check(routes_v4:, routes_v6: [])
    netif = Struct.new(:routes).new({ 4 => routes_v4, 6 => routes_v6 })
    cfg = instance_double(
      NodeCtld::VpsConfig::TopLevel,
      network_interfaces: [netif]
    )

    allow(NodeCtld::VpsConfig).to receive(:open).with('tank/ct', 101).and_return(cfg)

    described_class.new('tank/ct', 101)
  end

  it 'returns routes still present in kernel tables' do
    present = route('192.0.2.1/32')
    absent = route('198.51.100.0/24')
    check = build_check(routes_v4: [present, absent])
    route_list_v4 = instance_double(NodeCtld::RouteList)
    route_list_v6 = instance_double(NodeCtld::RouteList)

    allow(NodeCtld::RouteList).to receive(:new).with(4, anything).and_return(route_list_v4)
    allow(NodeCtld::RouteList).to receive(:new).with(6, anything).and_return(route_list_v6)
    allow(route_list_v4).to receive(:include?) { |addr| addr == present.address }
    allow(route_list_v6).to receive(:include?).and_return(false)

    expect(check.check).to eq([present])
  end

  it 'raises when routes remain' do
    present = route('192.0.2.1/32')
    check = build_check(routes_v4: [present])

    allow(check).to receive(:check).and_return([present])

    expect { check.check! }.to raise_error(/The following routes exist: 192.0.2.1/)
  end

  it 'waits until routes are cleared' do
    present = route('192.0.2.1/32')
    check = build_check(routes_v4: [present])

    allow(check).to receive(:check).and_return([present], [])
    allow(check).to receive(:sleep)
    allow(check).to receive(:log)

    expect(check.wait(timeout: 1)).to be_nil
    expect(check).to have_received(:sleep).with(5)
  end

  it 'raises with a formatted route list on timeout' do
    present = route('192.0.2.1/32')
    check = build_check(routes_v4: [present])

    allow(check).to receive(:check).and_return([present])

    expect { check.wait(timeout: -1) }.to raise_error(/the following routes exist: 192.0.2.1/)
  end
end
