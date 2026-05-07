# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/remote_control'
require 'nodectld/remote_commands/base'
require 'nodectld/remote_commands/queue'

RSpec.describe NodeCtld::RemoteCommands::Queue do
  let(:vps_queue) { NodeCtldSpec::FakeQueue.new }
  let(:network_queue) { NodeCtldSpec::FakeQueue.new }
  let(:queues) { { vps: vps_queue, network: network_queue } }
  let(:daemon) { instance_double(NodeCtldSpec::FakeDaemon, queues: queues) }

  it 'pauses one queue' do
    ret = described_class.new({ command: 'pause', queue: 'vps', duration: 30 }, daemon).exec

    expect(ret).to eq(ret: :ok)
    expect(vps_queue.paused_for).to eq([30])
  end

  it 'resumes one queue' do
    ret = described_class.new({ command: 'resume', queue: 'vps' }, daemon).exec

    expect(ret).to eq(ret: :ok)
    expect(vps_queue.resumed).to be(true)
  end

  it 'resumes all queues' do
    ret = described_class.new({ command: 'resume', queue: 'all' }, daemon).exec

    expect(ret).to eq(ret: :ok)
    expect(vps_queue.resumed).to be(true)
    expect(network_queue.resumed).to be(true)
  end

  it 'patches the queue thread count when resizing' do
    $CFG = runtime_cfg

    ret = described_class.new({ command: 'resize', queue: 'vps', size: 5 }, daemon).exec

    expect(ret).to eq(ret: :ok)
    expect($CFG.get(:vpsadmin, :queues, :vps, :threads)).to eq(5)
  end

  it 'returns an error when the queue does not exist' do
    ret = described_class.new({ command: 'pause', queue: 'missing' }, daemon).exec

    expect(ret).to eq(ret: :error, output: 'queue not found')
  end

  it 'returns an error for unknown commands' do
    ret = described_class.new({ command: 'bogus', queue: 'vps' }, daemon).exec

    expect(ret).to eq(ret: :error, output: 'unknown command')
  end
end
