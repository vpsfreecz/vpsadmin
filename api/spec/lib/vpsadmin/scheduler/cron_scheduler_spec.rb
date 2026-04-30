# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::Scheduler::CronScheduler do
  let(:scheduler) { scheduler_class.new(worker) }
  let(:worker) { instance_double(VpsAdmin::Scheduler::Worker, :<< => nil) }
  let(:stop_run) { Class.new(StandardError) }
  let(:scheduler_class) do
    Class.new(described_class) do
      attr_accessor :sleep_handler
      attr_reader :messages, :sleep_calls

      def initialize(*)
        super
        @messages = []
        @sleep_calls = []
      end

      def puts(message)
        @messages << message
      end

      def sleep(seconds)
        @sleep_calls << seconds
        sleep_handler&.call(seconds)
      end
    end
  end

  it 'adds and returns tasks by id' do
    scheduler.add_task(id: 1, class_name: 'Task', row_id: 10)

    task = scheduler.get_task(1)
    expect(task.id).to eq(1)
    expect(task.class_name).to eq('Task')
    expect(task.row_id).to eq(10)
    expect(scheduler.size).to eq(1)
    expect(scheduler.get_tasks).to eq(1 => task)
  end

  it 'replaces the task set atomically' do
    scheduler.add_task(id: 1, class_name: 'OldTask', row_id: 10)

    scheduler.replace do
      scheduler.add_task(id: 2, class_name: 'NewTask', row_id: 20)
    end

    expect(scheduler.get_task(1)).to be_nil
    expect(scheduler.get_task(2).class_name).to eq('NewTask')
    expect(scheduler.size).to eq(1)
  end

  it 'queues only matching tasks during a run tick' do
    scheduler.add_task(id: 1, class_name: 'A', row_id: 10, minute: '5')
    scheduler.add_task(id: 2, class_name: 'B', row_id: 20, minute: '6')

    allow(Time).to receive(:now).and_return(
      Time.new(2026, 1, 1, 0, 5, 0),
      Time.new(2026, 1, 1, 0, 5, 1)
    )
    scheduler.sleep_handler = proc { raise stop_run }

    expect do
      scheduler.send(:run)
    end.to raise_error(stop_run)

    expect(worker).to have_received(:<<).once
    expect(worker).to have_received(:<<).with(scheduler.get_task(1))
  end

  it 'sleeps until the next minute boundary' do
    allow(Time).to receive(:now).and_return(
      Time.new(2026, 1, 1, 0, 5, 20),
      Time.new(2026, 1, 1, 0, 5, 45)
    )
    scheduler.sleep_handler = proc { raise stop_run }

    expect do
      scheduler.send(:run)
    end.to raise_error(stop_run)

    expect(scheduler.sleep_calls).to eq([15])
  end
end
