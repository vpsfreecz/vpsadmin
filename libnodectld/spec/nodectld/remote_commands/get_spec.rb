# frozen_string_literal: true

require 'spec_helper'
require 'time'
require 'nodectld/remote_control'
require 'nodectld/remote_commands/base'
require 'nodectld/remote_commands/get'
require 'nodectld/veth_map'
require 'nodectld/net_accounting'

RSpec.describe NodeCtld::RemoteCommands::Get do
  it 'returns the current config' do
    ret = described_class.new({ resource: 'config' }, nil).exec

    expect(ret[:ret]).to eq(:ok)
    expect(ret[:output][:config]).to include(:vpsadmin)
  end

  it 'returns queued transactions and skips those already executing' do
    queues = instance_double(NodeCtld::Queues)
    daemon = instance_double(NodeCtldSpec::FakeDaemon, queues: queues)
    db = instance_double(NodeCtld::Db, close: nil)
    rows = [
      {
        'id' => 10,
        'transaction_chain_id' => 20,
        'chain_state' => 1,
        'handle' => '77',
        'created_at' => '2026-01-01 00:00:00',
        'user_id' => 5,
        'vps_id' => 6,
        'depends_on_id' => nil,
        'urgent' => 1,
        'priority' => 9,
        'input' => { 'a' => 1 }
      },
      {
        'id' => 11,
        'transaction_chain_id' => 21,
        'chain_state' => 3,
        'handle' => '78',
        'created_at' => '2026-01-01 00:00:01',
        'user_id' => 7,
        'vps_id' => 8,
        'depends_on_id' => 10,
        'urgent' => 0,
        'priority' => 1,
        'input' => {}
      }
    ]

    allow(NodeCtld::Db).to receive(:new).and_return(db)
    allow(daemon).to receive(:select_commands).with(db, 50).and_return(rows)
    allow(queues).to receive(:has_transaction?) { |id| id == 10 }

    ret = described_class.new({ resource: 'queue', limit: 50 }, daemon).exec

    expect(ret[:ret]).to eq(:ok)
    expect(ret[:output][:queue]).to eq([
                                         {
                                           id: 11,
                                           chain: 21,
                                           state: 3,
                                           type: 78,
                                           time: Time.parse('2026-01-01 00:00:01 UTC').localtime.to_i,
                                           m_id: 7,
                                           vps_id: 8,
                                           depends_on: 10,
                                           urgent: false,
                                           priority: 1,
                                           params: {}
                                         }
                                       ])
  end

  it 'returns the veth map' do
    allow(NodeCtld::VethMap).to receive(:dump).and_return('101' => { 'eth0' => 'veth101' })

    ret = described_class.new({ resource: 'veth_map' }, nil).exec

    expect(ret).to eq(ret: :ok, output: { veth_map: { '101' => { 'eth0' => 'veth101' } } })
  end

  it 'returns net accounting interfaces' do
    allow(NodeCtld::NetAccounting).to receive(:dump).and_return([{ vps_id: 101 }])

    ret = described_class.new({ resource: 'net_accounting' }, nil).exec

    expect(ret).to eq(ret: :ok, output: { interfaces: [{ vps_id: 101 }] })
  end

  it 'raises a system command failure for unknown resources' do
    expect do
      described_class.new({ resource: 'unknown' }, nil).exec
    end.to raise_error(NodeCtld::SystemCommandFailed) { |err|
      expect(err.output).to eq('Unknown resource unknown')
    }
  end
end
