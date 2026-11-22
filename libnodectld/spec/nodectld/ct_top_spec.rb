# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/ct_top'
require 'stringio'

RSpec.describe NodeCtld::CtTop do
  let(:frame) do
    JSON.parse(File.read(File.expand_path('../fixtures/partial_memory_failure.json', __dir__)), symbolize_names: true)
  end
  let(:base_argv) { %w[osctl -j ct top --rate 120 --no-iostat --no-processes] }
  let(:clock) { 116_000_000_000 }
  let(:top) { described_class.new.tap { |reader| reader.instance_variable_set(:@rate, 120) } }

  before do
    allow(Process).to receive(:clock_gettime).and_call_original
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC, :nanosecond).and_return(clock)
  end

  after { top.stop }

  def complete_frame
    a, b, host = frame.fetch(:containers)
    frame.merge(complete: true, invalid_reason: nil, measurement_window_started_monotonic_ns: 100_000_000_000,
                containers: [a, b.merge(memory: 100, errors: {}), host])
  end

  def wire(*frames)
    frames.map { |value| "#{value.to_json}\n" }.join
  end

  def samples(text)
    result = []
    top.send(:read_samples, StringIO.new(text)) { |sample| result << sample }
    result
  end

  it 'consumes bare schema 2 with unchanged argv and refuses old or wrapped records' do
    rejected = [frame.except(:top_schema), frame.merge(top_schema: 1), frame.merge(top_schema: 2.0),
                frame.merge(top_schema: 1, observation: frame), frame.merge(observation: nil)]
    expect(samples(wire(*rejected))).to be_empty
    allow(Process).to receive(:spawn).with(*base_argv, out: an_instance_of(IO), close_others: true) do |*_, out:, **|
      out.write(wire(frame))
      123
    end
    allow(Process).to receive(:wait2).with(123).and_return([123, instance_double(Process::Status, exitstatus: 0)])
    result = []
    top.send(:run) { |sample| result << sample.sequence }
    expect(result).to eq([7])
  end

  it 'binds an epoch per spawned child and does not accept a retired epoch in a replacement' do
    streams = [[frame], [frame.merge(epoch: 'second')], [frame.merge(sequence: 8), frame.merge(epoch: 'third')]]
    allow(Process).to receive(:spawn).with(*base_argv, out: an_instance_of(IO), close_others: true) do |*_, out:, **|
      out.write(wire(*streams.shift))
      123
    end
    allow(Process).to receive(:wait2).with(123).and_return([123, instance_double(Process::Status, exitstatus: 0)])
    result = []
    3.times { top.send(:run) { |sample| result << [sample.epoch, sample.sequence] } }
    expect(result).to eq([['fixture-e', 7], ['second', 7], ['third', 7]])
  end

  it 'rejects oversized and unterminated records, duplicates and an epoch change within one child' do
    stub_const('NodeCtld::CtTop::MAX_FRAME_BYTES', frame.to_json.bytesize + 10)
    oversized = 'x' * (described_class::MAX_FRAME_BYTES + 30)
    other = frame.merge(epoch: 'other', sequence: 8)
    text = "#{oversized}\n{broken\n#{wire(frame, frame, other)}#{frame.to_json}"
    expect(samples(text).map(&:sequence)).to eq([7])
  end

  it 'rejects impossible or expired clocks, invalid host sentinel and contradictory closed membership' do
    a, b, host = frame.fetch(:containers)
    stale = frame.merge(sample_started_monotonic_ns: 5, sample_completed_monotonic_ns: 10,
                        previous_sample_started_monotonic_ns: 1, measurement_window_completed_monotonic_ns: 10)
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC, :nanosecond).and_return(121_000_000_000)
    variants = [stale, frame.merge(sample_completed_monotonic_ns: 121_000_000_001), frame.merge(measurement_window_completed_monotonic_ns: 0),
                frame.merge(state_counts: { running: 3 }), frame.merge(containers: [a, b, b, host]),
                frame.merge(containers: [a, b.merge(run_verified: false), host]),
                frame.merge(containers: [a, b, host.except(:init_start_time_ticks)]), frame.merge(containers: [a, b]),
                frame.merge(containers: [host, a, b]), frame.merge(containers: [host, a, b, host])]
    expect(samples(wire(*variants))).to be_empty
  end

  it 'distinguishes the same CT ID in different pools in a closed roster' do
    a, b, host = frame.fetch(:containers)
    same_id = b.merge(pool: 'other', id: a[:id])
    expect(samples(wire(frame.merge(containers: [a, same_id, host]))).map(&:sequence)).to eq([7])
  end

  it 'requires explicit nullable header fields without treating unknown measurements as a structural failure' do
    a, b, host = frame.fetch(:containers)
    good = frame.merge(loadavg: nil, containers: [a, b, host.merge(loadavg: nil)])
    variants = [good.except(:loadavg), good.except(:measurement_window_started_monotonic_ns),
                good.merge(containers: [a, b, host.except(:loadavg)]), frame.except(:invalid_reason)]
    expect(samples(wire(*variants))).to be_empty
    expect(samples(wire(good)).map(&:sequence)).to eq([7])
  end

  it 'rejects invalid complete claims and preserves a valid complete frame' do
    full = complete_frame
    a, b, host = full[:containers]
    variants = [full.merge(loadavg: nil, containers: [a, b, host.merge(loadavg: nil)]), full.merge(inventory_complete: false),
                full.merge(containers: [a.merge(cpu_limit: nil, cpu_limit_state: 'unknown'), b, host]),
                full.merge(containers: [a.merge(cpu_baseline_sequence: 5), b, host]),
                full.merge(containers: [a.merge(errors: { memory: 'missing_cgroup_value' }), b, host]),
                full.merge(containers: [a.merge(nproc: '12'), b, host]),
                full.merge(containers: [a.merge(errors: { nproc: 'missing_cgroup_value' }), b, host])]
    expect(samples(wire(*variants))).to be_empty
    expect(samples(wire(full)).map(&:sequence)).to eq([7])
  end

  it 'enforces adjacent raw windows and rejects overlap without refreshing age' do
    next_header = { sequence: 8, sample_started_monotonic_ns: 115_400_000_000, sample_completed_monotonic_ns: 115_800_000_000,
                    measurement_window_completed_monotonic_ns: 115_800_000_000 }
    nxt = frame.merge(next_header)
    overlap = nxt.merge(previous_sample_started_monotonic_ns: frame[:sample_started_monotonic_ns],
                        sample_started_monotonic_ns: 115_100_000_000)
    fixed = nxt.merge(previous_sample_started_monotonic_ns: frame[:sample_started_monotonic_ns])
    expect(samples(wire(frame, nxt, overlap)).map(&:sequence)).to eq([7])
    expect(samples(wire(frame, fixed)).map(&:sequence)).to eq([7, 8])
  end

  it 'requests a new sample with USR1 after a lifecycle refresh' do
    now = Time.utc(2026, 1, 1)
    allow(Time).to receive(:now).and_return(now, now + 4)
    allow(Process).to receive(:kill).with('USR1', 123)
    # Run the real refresh block once, without timing a background thread.
    actual = nil
    allow(Thread).to receive(:new) do |&block|
      actual = block
      instance_double(Thread, terminate: nil)
    end
    top.instance_variable_set(:@pid, 123)
    top.refresh
    allow(top).to receive(:sleep).with(10).and_invoke(proc {}, proc { raise Interrupt })
    expect { actual.call }.to raise_error(Interrupt)
    expect(Process).to have_received(:kill).with('USR1', 123).once
  end
end
