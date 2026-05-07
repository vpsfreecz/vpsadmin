# frozen_string_literal: true

require 'spec_helper'
require 'ostruct'
require 'nodectld/remote_control'
require 'nodectld/remote_commands/base'
require 'nodectld/remote_commands/status'

RSpec.describe NodeCtld::RemoteCommands::Status do
  it 'returns daemon, queue, console, and subprocess state' do
    worker_cmd = NodeCtldSpec::FakeCmd.new(
      id: 100,
      chain_id: 10,
      queue: :vps,
      urgent: false,
      current_chain_direction: :execute,
      handler: 'NodeCtld::Commands::Vps::Start',
      progress: { current: 1, total: 2, time: Time.at(111) },
      time_start: Time.at(100),
      step: 'exec',
      subtask: 1234,
      trans: { 'handle' => '77' }
    )
    queue = NodeCtldSpec::FakeQueue.new(
      threads: 2,
      urgent: 1,
      open: true,
      started: true,
      start_delay: 0,
      reservations: [42],
      workers: { 10 => NodeCtldSpec::FakeWorker.new(worker_cmd) }
    )
    queues = instance_double(NodeCtld::Queues, worker_count: 1)
    daemon = instance_double(
      NodeCtldSpec::FakeDaemon,
      queues: queues,
      console: double(stats: { 101 => 2 }),
      initialized?: true,
      run?: true,
      paused?: nil,
      exitstatus: 0,
      last_transaction_check: Time.at(200),
      start_time: Time.at(50)
    )
    db = instance_double(NodeCtld::Db)

    allow(queues).to receive(:each).and_yield(:vps, queue)
    allow(daemon).to receive(:chain_blockers).and_yield({ 10 => [555] })
    allow(NodeCtld::Db).to receive(:new).and_return(db)
    allow(db).to receive(:prepared).and_return(double(get: { 'cnt' => 5 }))

    ret = described_class.new({}, daemon).exec

    expect(ret[:ret]).to eq(:ok)
    expect(ret[:output][:state]).to eq(
      initialized: true,
      run: true,
      pause: nil,
      status: 0
    )
    expect(ret[:output][:queues][:vps]).to include(
      threads: 2,
      urgent: 1,
      open: true,
      start_delay: 0,
      started: true,
      reservations: [42]
    )
    expect(ret[:output][:queues][:vps][:workers][10]).to include(
      id: 100,
      type: 77,
      handler: 'Vps::Start',
      step: 'exec',
      pid: 1234,
      start: Time.at(100).localtime.to_i,
      progress: { current: 1, total: 2, time: 111 }
    )
    expect(ret[:output]).to include(
      export_console: true,
      consoles: { 101 => 2 },
      subprocesses: { 10 => [555] },
      last_transaction_check: 200,
      start_time: 50,
      queue_size: 4
    )
  end
end
