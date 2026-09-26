# frozen_string_literal: true

require 'spec_helper'
require 'timeout'
require 'nodectld/worker'
require 'nodectld/queues'
require 'nodectld/node_activity'

RSpec.describe NodeCtld::NodeActivity do
  let(:activity) { described_class.new }
  let(:queues) do
    $CFG = runtime_cfg
    NodeCtld::Queues.new(
      instance_double(NodeCtldSpec::FakeDaemon, start_time: Time.now - 10),
      activity:
    )
  end
  let(:blockers) { ->(**_kwargs) { 0 } }

  def command(id, handle:, direction: :execute, queue: :storage)
    NodeCtldSpec::FakeCmd.new(
      id:, chain_id: id + 100, queue:, urgent: false, priority: 0,
      current_chain_direction: direction, type: handle
    )
  end

  def sample
    activity.snapshot(queues:, blockers:)
  end

  it 'reports every queue and keeps child coverage explicitly unknown' do
    first = sample
    second = described_class.new.snapshot(queues:, blockers:)

    expect(first).to include(
      version: 1, coverage: 'node_activity_v1', effect_generation: 0,
      child_coverage: 'unknown', unknown: true, overflow: false,
      detached_blockers: 0, tracked_children: 0
    )
    expect(first[:daemon_boot_uuid]).to match(/\A[0-9a-f-]{36}\z/)
    expect(first[:daemon_boot_uuid]).not_to eq(second[:daemon_boot_uuid])
    expect(first[:queues].keys).to match_array(NodeCtld::Queues::QUEUES)
    expect(first[:queues].values).to all(eq(workers: 0, reservations: 0))
    expect(first[:unknown_reasons]).to include('child_lifetime_unproved')
    expect(first).not_to have_key(:node_quiet)
    expect(first).not_to have_key(:repair_ready)
  end

  it 'brackets effectful execute, rollback, and unknown handles but not inventory' do
    inventory = command(1, handle: 5290)
    queues.execute(inventory)
    expect(sample[:queues][:inventory][:workers]).to eq(1)
    expect(sample[:effect_generation]).to eq(0)

    activity_probe = command(8, handle: 5291)
    queues.execute(activity_probe)
    expect(sample[:effect_generation]).to eq(0)
    expect(sample[:queues][:inventory][:workers]).to eq(2)
    excluded = activity.snapshot(
      queues:, blockers:, excluding_transaction_id: activity_probe.id
    )
    expect(excluded[:queues][:inventory][:workers]).to eq(1)
    expect(excluded[:unknown_reasons]).not_to include('probe_worker_unproved')
    queues[:inventory].delete_if(saved: true) { true }
    expect(sample[:effect_generation]).to eq(0)

    [command(2, handle: 5204), command(3, handle: 5204, direction: :rollback),
     command(4, handle: 99_999)].each_with_index do |cmd, index|
      queues.execute(cmd)
      expect(sample[:effect_generation]).to eq((index * 2) + 1)
      queues[cmd.current_chain_direction == :rollback ? :rollback : :storage]
        .delete_if(saved: true) { true }
      expect(sample[:effect_generation]).to eq((index + 1) * 2)
    end
  end

  it 'retains a worker through the save callback and records an unsaved clear' do
    cmd = command(5, handle: 5204)
    queues.execute(cmd)
    queue = queues[:storage]

    queue.delete_if(saved: true) do
      expect(sample[:queues][:storage][:workers]).to eq(1)
      true
    end
    expect(sample[:queues][:storage][:workers]).to eq(0)
    expect(sample[:effect_generation]).to eq(2)

    queues.execute(command(6, handle: 5204))
    queue.clear!
    expect(sample[:unknown_reasons]).to include('worker_removed_without_save')
  end

  it 'keeps a hard-kill outcome unknown even after the worker is saved' do
    cmd = command(7, handle: 5204)
    cmd.define_singleton_method(:killed) { |_hard| nil }
    worker = queues.execute(cmd)
    worker.kill
    queues[:storage].delete_if(saved: true) { true }

    expect(sample[:unknown_reasons]).to include('worker_killed_child_unproved')
    expect(sample[:effect_generation]).to be >= 3
  end

  it 'tracks reservation and registered child changes without claiming child proof' do
    queue = queues[:vps]
    queue.reserve(30)
    expect(sample[:queues][:vps][:reservations]).to eq(1)
    expect(sample[:effect_generation]).to eq(2)
    queue.release(30)

    child = activity.child_begin
    child_sample = activity.snapshot(queues:, blockers: ->(**_kwargs) { 1 })
    expect(child_sample[:tracked_children]).to eq(1)
    expect(child_sample[:detached_blockers]).to eq(1)
    activity.child_finished(child)
    expect(sample[:tracked_children]).to eq(0)
    expect(sample[:child_coverage]).to eq('unknown')
  end

  it 'keeps read-only reservations out of effect generation' do
    queue = queues[:vps]

    queues.reserve(:vps, command(31, handle: 5290, queue: :vps))
    expect(sample[:queues][:vps][:reservations]).to eq(1)
    expect(sample[:effect_generation]).to eq(0)
    queue.release(131)
    expect(sample[:effect_generation]).to eq(0)

    [5204, 101, 99_999].each_with_index do |handle, index|
      cmd = command(index + 32, handle:, queue: :vps)
      queues.reserve(:vps, cmd)
      expect(sample[:effect_generation]).to eq((index * 4) + 2)
      queue.release(cmd.chain_id)
      expect(sample[:effect_generation]).to eq((index + 1) * 4)
    end
  end

  it 'returns unknown by deadline when a blocked reservation owns the global queue lock' do
    queue = queues[:vps]
    queue.reserve(40)
    queue.reserve(42)
    waiting = Thread.new do
      queues.reserve(:vps, command(41, handle: 5204, queue: :vps))
    end
    Timeout.timeout(2) do
      sleep 0.001 until queues.instance_variable_get(:@mutex).locked?
    end

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = activity.snapshot(queues:, blockers:, timeout: 0.02)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    expect(elapsed).to be < 0.5
    expect(result[:queues]).to be_nil
    expect(result[:unknown_reasons]).to include('queue_snapshot_unavailable')
  ensure
    queue&.release(40)
    queue&.release(42)
    waiting&.join(2)
    queue&.release(141)
  end

  it 'rejects a missing queue and caps malformed counts' do
    queues.instance_variable_get(:@queues).delete(:rollback)
    expect(sample[:unknown_reasons]).to include('queue_snapshot_unavailable')

    allow(queues).to receive(:activity_counts).and_return(
      general: { workers: described_class::COUNT_CAP + 1, reservations: 0 }
    )
    result = sample
    expect(result[:overflow]).to be(true)
    expect(result[:queues][:general][:workers]).to eq(described_class::COUNT_CAP)
    expect(result[:unknown_reasons]).to include('count_overflow')
  end

  it 'rejects a snapshot changed while queue counts were sampled' do
    allow(queues).to receive(:activity_counts).and_wrap_original do |original, **kwargs|
      counts = original.call(**kwargs)
      activity.reservation_begin
      activity.reservation_end
      counts
    end
    expect(sample[:unknown_reasons]).to include('sample_changed')
  end
end
