# frozen_string_literal: true

require 'spec_helper'
require 'timeout'
require 'nodectld/worker'
require 'nodectld/queues'
require 'nodectld/transaction_queue'

RSpec.describe NodeCtld::TransactionQueue do
  def build_queue(threads: 1, urgent: 1, start_delay: 0, start_time: Time.now - 10)
    $CFG = runtime_cfg(
      vpsadmin: {
        queues: {
          vps: {
            threads: threads,
            urgent: urgent,
            start_delay: start_delay
          }
        }
      }
    )
    described_class.new(:vps, start_time)
  end

  def fake_cmd(id, chain_id: id, urgent: false, priority: 0)
    NodeCtldSpec::FakeCmd.new(
      id: id,
      chain_id: chain_id,
      queue: :vps,
      urgent: urgent,
      priority: priority,
      current_chain_direction: :execute
    )
  end

  it 'executes a command when open and started' do
    queue = build_queue

    expect(queue.execute(fake_cmd(1))).to be_a(NodeCtld::Worker)
    expect(queue.has_transaction?(1)).to be(true)
  end

  it 'requires a free normal slot for non-urgent commands' do
    queue = build_queue(threads: 1, urgent: 1)

    expect(queue.execute(fake_cmd(1))).to be_truthy
    expect(queue.execute(fake_cmd(2))).to be(false)
  end

  it 'allows urgent commands to use urgent capacity' do
    queue = build_queue(threads: 1, urgent: 1)

    expect(queue.execute(fake_cmd(1))).to be_truthy
    expect(queue.execute(fake_cmd(2, urgent: true))).to be_truthy
    expect(queue.execute(fake_cmd(3, urgent: true))).to be(false)
  end

  it 'lets reserved chains bypass the normal free-slot path' do
    queue = build_queue(threads: 1, urgent: 0)

    expect(queue.reserve(2)).to be(true)
    expect(queue.execute(fake_cmd(2))).to be_truthy
    expect(queue.execute(fake_cmd(3))).to be(false)
  end

  it 'reserves and releases chain ids' do
    queue = build_queue

    expect(queue.reserve(9)).to be(true)
    expect(queue.reservations).to eq([9])
    expect(queue.release(9)).to be(true)
    expect(queue.reservations).to eq([])
    expect(queue.release(9)).to be(false)
  end

  it 'pauses and resumes queue admission' do
    queue = build_queue

    queue.pause
    expect(queue.open?).to be(false)

    queue.resume
    expect(queue.open?).to be(true)
  end

  it 'reports whether the queue start delay has elapsed' do
    queue = build_queue(start_delay: 60, start_time: Time.now)

    expect(queue.started?).to be(false)
  end

  it 'releases semaphore slots when deleting non-urgent non-reserved commands' do
    queue = build_queue(threads: 1, urgent: 0)

    expect(queue.execute(fake_cmd(1))).to be_truthy
    expect(queue.execute(fake_cmd(2))).to be(false)

    queue.delete_if { true }

    worker = nil
    Timeout.timeout(2) do
      until worker
        worker = queue.execute(fake_cmd(2))
        sleep 0.01 unless worker
      end
    end

    expect(worker).to be_truthy
  end

  it 'updates queue limits through the config callback' do
    queue = build_queue(threads: 1, urgent: 0, start_delay: 0)

    $CFG.patch(vpsadmin: { queues: { vps: { threads: 3, urgent: 2, start_delay: 5 } } })

    expect(queue.size).to eq(3)
    expect(queue.urgent_size).to eq(2)
    expect(queue.start_delay).to eq(5)
  end

  describe NodeCtld::TransactionQueue::Semaphore do
    def wait_for_result(results, count)
      Timeout.timeout(2) do
        sleep 0.01 until results.length >= count
      end
    end

    it 'preserves FIFO ordering within the same priority' do
      sem = described_class.new(1)
      sem.start
      results = Queue.new

      sem.down_now
      first = Thread.new do
        sem.down_block(priority: 5)
        results << :first
      end
      sleep 0.05
      second = Thread.new do
        sem.down_block(priority: 5)
        results << :second
      end
      sleep 0.05

      sem.up
      wait_for_result(results, 1)
      sem.up
      wait_for_result(results, 2)

      expect([results.pop, results.pop]).to eq(%i[first second])

      first.join
      second.join
    end

    it 'lets higher priority waiters run first' do
      sem = described_class.new(1)
      sem.start
      results = Queue.new

      sem.down_now
      low = Thread.new do
        sem.down_block(priority: 1)
        results << :low
      end
      sleep 0.05
      high = Thread.new do
        sem.down_block(priority: 10)
        results << :high
      end
      sleep 0.05

      sem.up
      wait_for_result(results, 1)
      sem.up
      wait_for_result(results, 2)

      expect([results.pop, results.pop]).to eq(%i[high low])

      low.join
      high.join
    end

    it 'wakes waiting items when resized upward' do
      sem = described_class.new(1)
      sem.start
      results = Queue.new

      sem.down_now
      waiter = Thread.new do
        sem.down_block
        results << :woken
      end
      sleep 0.05

      sem.resize(2)
      wait_for_result(results, 1)

      expect(results.pop).to eq(:woken)

      waiter.join
    end
  end
end
