# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::Scheduler::CronTask do
  it 'parses wildcard fields as complete cron ranges' do
    task = described_class.new(id: 1, class_name: 'Task', row_id: 2)

    expect(task.minute).to eq((0..59).to_a)
    expect(task.hour).to eq((0..23).to_a)
    expect(task.day).to eq((1..31).to_a)
    expect(task.month).to eq((1..12).to_a)
    expect(task.weekday).to eq((0..6).to_a)
  end

  it 'parses numeric fields as single-value ranges' do
    task = described_class.new(
      id: 1,
      class_name: 'Task',
      row_id: 2,
      minute: '15',
      hour: '6',
      day: '10',
      month: '4',
      weekday: '5'
    )

    expect(task.minute).to eq([15])
    expect(task.hour).to eq([6])
    expect(task.day).to eq([10])
    expect(task.month).to eq([4])
    expect(task.weekday).to eq([5])
  end

  it 'matches wildcard schedules' do
    task = described_class.new(id: 1, class_name: 'Task', row_id: 2)

    expect(task.matches?(Time.new(2026, 1, 2, 3, 4, 0))).to be(true)
  end

  it 'matches five-minute snapshots and offset ten-minute backups exactly' do
    snapshots = described_class.new(id: 1, class_name: 'Task', row_id: 2, minute: '*/5')
    backups = described_class.new(id: 2, class_name: 'Task', row_id: 3, minute: '2-59/10')

    expect(snapshots.minute).to eq([0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55])
    expect(backups.minute).to eq([2, 12, 22, 32, 42, 52])
    60.times do |minute|
      time = Time.new(2026, 1, 2, 3, minute, 0)
      expect(snapshots.matches?(time)).to eq(minute % 5 == 0)
      expect(backups.matches?(time)).to eq([2, 12, 22, 32, 42, 52].include?(minute))
    end
  end

  it 'starts stepped wildcards at each field minimum and includes range endpoints' do
    task = described_class.new(id: 1, class_name: 'Task', row_id: 2,
                               day: '*/10', month: '2-12/5', weekday: '1-5/2')

    expect(task.day).to eq([1, 11, 21, 31])
    expect(task.month).to eq([2, 7, 12])
    expect(task.weekday).to eq([1, 3, 5])
  end

  it 'rejects malformed, wrapping, out-of-range and unsupported minute fields' do
    ['', 'oops', '5oops', ' 5', '-1', '60', '*/0', '*/-5', '*/61',
     '10-2/5', '0-60/5', '1-5', '0,5', '*/5tail', '*/5/2'].each do |field|
      expect do
        described_class.new(id: 1, class_name: 'Task', row_id: 2, minute: field)
      end.to raise_error(described_class::InvalidField)
    end
  end

  it 'enforces the bounds and maximum step of every field' do
    { hour: '*/25', day: '0-31/5', month: '1-13/2', weekday: '*/8' }.each do |name, field|
      expect do
        described_class.new(id: 1, class_name: 'Task', row_id: 2, **{ name => field })
      end.to raise_error(described_class::InvalidField)
    end
  end

  it 'matches only configured numeric fields' do
    task = described_class.new(
      id: 1,
      class_name: 'Task',
      row_id: 2,
      minute: '15',
      hour: '6',
      day: '10',
      month: '4',
      weekday: '5'
    )

    expect(task.matches?(Time.new(2026, 4, 10, 6, 15, 0))).to be(true)
    expect(task.matches?(Time.new(2026, 4, 10, 6, 16, 0))).to be(false)
    expect(task.matches?(Time.new(2026, 4, 10, 7, 15, 0))).to be(false)
    expect(task.matches?(Time.new(2026, 4, 11, 6, 15, 0))).to be(false)
    expect(task.matches?(Time.new(2026, 5, 10, 6, 15, 0))).to be(false)
    expect(task.matches?(Time.new(2026, 4, 9, 6, 15, 0))).to be(false)
  end

  it 'exports scheduler payload attributes' do
    task = described_class.new(
      id: 7,
      class_name: 'Task',
      row_id: 9,
      minute: '1',
      hour: '2',
      day: '3',
      month: '4',
      weekday: '5'
    )

    expect(task.export).to eq(
      id: 7,
      class_name: 'Task',
      row_id: 9,
      minute: [1],
      hour: [2],
      day: [3],
      month: [4],
      weekday: [5]
    )
  end
end
