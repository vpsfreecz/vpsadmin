# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/queues'
require 'nodectld/veth_map'

RSpec.describe NodeCtld::VethMap do
  def build_map(netifs = [])
    map = described_class.send(:allocate)

    map.instance_variable_set(:@map, {})
    map.instance_variable_set(:@mutex, Mutex.new)
    allow(map).to receive(:list_all).and_return(netifs)
    map.send(:load_all)
    map
  end

  it 'sets, gets, and resets mappings' do
    map = build_map

    map.set(101, 'eth0', 'veth101')

    expect(map.get(101, 'eth0')).to eq('veth101')

    map.reset(101)

    expect(map.get(101, 'eth0')).to be_nil
  end

  it 'rebuilds all mappings from osctl output' do
    map = build_map([{ ctid: '101', name: 'eth0', veth: 'old' }])

    allow(map).to receive(:list_all).and_return([
                                                  { ctid: '102', name: 'eth0', veth: 'veth102' },
                                                  { ctid: '103', name: 'eth0', veth: nil }
                                                ])

    map.update_all

    expect(map.dump).to eq('102' => { 'eth0' => 'veth102' })
  end

  it 'returns a copy from dump' do
    map = build_map

    map.set(101, 'eth0', 'veth101')
    dumped = map.dump
    dumped['101']['eth0'] = 'changed'

    expect(map.get(101, 'eth0')).to eq('veth101')
  end

  it 'iterates only host mappings with real host veth names' do
    map = build_map
    yielded = []

    map.set(101, 'eth0', 'veth101')
    map.set(101, 'eth1', nil)
    map.each_veth { |*args| yielded << args }

    expect(yielded).to eq([%w[101 eth0 veth101]])
  end
end
