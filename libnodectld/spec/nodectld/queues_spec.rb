# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/worker'
require 'nodectld/queues'

RSpec.describe NodeCtld::Queues do
  def build_queues
    $CFG = runtime_cfg
    described_class.new(instance_double(NodeCtldSpec::FakeDaemon, start_time: Time.now - 10))
  end

  def fake_cmd(id, queue: :vps, direction: :execute, priority: 0, type: 0)
    NodeCtldSpec::FakeCmd.new(
      id: id,
      chain_id: id + 100,
      queue: queue,
      urgent: false,
      priority: priority,
      current_chain_direction: direction,
      type:
    )
  end

  it 'routes execute-direction commands to the transaction queue' do
    queues = build_queues
    cmd = fake_cmd(1, queue: :vps)

    expect(queues.execute(cmd)).to be_truthy
    expect(queues[:vps].busy?(cmd.chain_id)).to be(true)
  end

  it 'routes rollback-direction commands to the rollback queue' do
    queues = build_queues
    cmd = fake_cmd(1, queue: :vps, direction: :rollback)

    expect(queues.execute(cmd)).to be_truthy
    expect(queues[:rollback].busy?(cmd.chain_id)).to be(true)
    expect(queues[:vps].busy?(cmd.chain_id)).to be(false)
  end

  it 'uses the inventory worker for persisted storage handle 5290' do
    queues = build_queues
    cmd = fake_cmd(1, queue: :storage, type: 5290)

    allow(queues[:inventory]).to receive(:free_slot?).and_return(false, true)
    expect(queues.free_slot?(cmd)).to be(false)
    expect(queues.free_slot?(cmd)).to be(true)
    expect(queues.execute(cmd)).to be_truthy
    expect(queues[:inventory].busy?(cmd.chain_id)).to be(true)
    expect(queues[:storage].busy?(cmd.chain_id)).to be(false)
  end

  it 'routes persisted storage handle 5291 to inventory, including free-slot checks' do
    queues = build_queues
    cmd = fake_cmd(3, queue: :storage, type: 5291)

    allow(queues[:inventory]).to receive(:free_slot?).and_return(false, true)
    expect(queues.free_slot?(cmd)).to be(false)
    expect(queues.free_slot?(cmd)).to be(true)
    expect(queues.execute(cmd)).to be_truthy
    expect(queues[:inventory].busy?(cmd.chain_id)).to be(true)
    expect(queues[:storage].busy?(cmd.chain_id)).to be(false)
  end

  it 'keeps rollback routing ahead of the inventory alias' do
    queues = build_queues
    cmd = fake_cmd(2, queue: :storage, direction: :rollback, type: 5290)

    expect(queues.execute(cmd)).to be_truthy
    expect(queues[:rollback].busy?(cmd.chain_id)).to be(true)
    expect(queues[:inventory].busy?(cmd.chain_id)).to be(false)
  end

  it 'reports busy chains, free slots, and executing transactions' do
    queues = build_queues
    cmd = fake_cmd(1, queue: :network)

    expect(queues.free_slot?(cmd)).to be(true)
    expect(queues.execute(cmd)).to be_truthy
    expect(queues.busy?(cmd.chain_id)).to be(true)
    expect(queues.has_transaction?(cmd.id)).to be(true)
  end

  it 'reserves queues and prunes finished chain reservations' do
    queues = build_queues
    cmd = fake_cmd(1, queue: :vps, priority: 9)
    db = instance_double(NodeCtld::Db)

    queues.reserve(%i[vps network], cmd)

    expect(queues[:vps].reservations).to eq([cmd.chain_id])
    expect(queues[:network].reservations).to eq([cmd.chain_id])

    allow(db).to receive(:query).and_return([{ 'id' => cmd.chain_id }])

    expect(queues.prune_reservations(db)).to eq(2)
    expect(queues[:vps].reservations).to eq([])
    expect(queues[:network].reservations).to eq([])
  end

  it 'reports worker count and total limits' do
    queues = build_queues

    queues.execute(fake_cmd(1, queue: :vps))
    queues.execute(fake_cmd(2, queue: :network))

    expect(queues.worker_count).to eq(2)
    expect(queues.total_limit).to eq(NodeCtld::Queues::QUEUES.length * 3)
  end
end
