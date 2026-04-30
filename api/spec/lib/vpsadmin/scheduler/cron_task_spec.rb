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
