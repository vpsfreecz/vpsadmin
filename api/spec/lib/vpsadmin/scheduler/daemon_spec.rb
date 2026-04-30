# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::Scheduler::Daemon do
  let(:daemon) { daemon_class.new }
  let(:daemon_class) do
    Class.new(described_class) do
      attr_reader :messages, :replace_count

      def initialize
        super
        @messages = []
        @replace_count = 0
      end

      def puts(message)
        @messages << message
      end

      def replace_tasks
        @replace_count += 1
      end
    end
  end
  let(:stop_run) { Class.new(StandardError) }

  it 'pushes update notifications to the internal queue' do
    queue = instance_double(Queue)
    daemon.instance_variable_set(:@queue, queue)

    allow(queue).to receive(:<<)

    daemon.update

    expect(queue).to have_received(:<<).with(:update)
  end

  it 'loads repeatable tasks in id order and maps cron fields' do
    base_daemon = described_class.new
    scheduler = instance_double(VpsAdmin::Scheduler::CronScheduler)
    first = RepeatableTask.create!(
      class_name: 'DatasetAction',
      table_name: 'dataset_actions',
      row_id: 101,
      minute: '5',
      hour: '6',
      day_of_month: '7',
      month: '8',
      day_of_week: '2'
    )
    second = RepeatableTask.create!(
      class_name: 'GroupSnapshot',
      table_name: 'group_snapshots',
      row_id: 202,
      minute: '10',
      hour: '11',
      day_of_month: '12',
      month: '1',
      day_of_week: '4'
    )

    base_daemon.instance_variable_set(:@scheduler, scheduler)
    allow(scheduler).to receive(:replace).and_yield
    allow(scheduler).to receive(:add_task)

    base_daemon.send(:replace_tasks)

    expect(scheduler).to have_received(:add_task).with(
      id: first.id,
      class_name: 'DatasetAction',
      row_id: 101,
      minute: '5',
      hour: '6',
      day: '7',
      month: '8',
      weekday: '2'
    ).ordered
    expect(scheduler).to have_received(:add_task).with(
      id: second.id,
      class_name: 'GroupSnapshot',
      row_id: 202,
      minute: '10',
      hour: '11',
      day: '12',
      month: '1',
      weekday: '4'
    ).ordered
  end

  it 'starts collaborators and blocks on queue pop in the run loop' do
    worker = instance_double(VpsAdmin::Scheduler::Worker, start: true)
    scheduler = instance_double(VpsAdmin::Scheduler::CronScheduler, start: true, size: 0)
    server = instance_double(VpsAdmin::Scheduler::Server, start: true)
    queue = instance_double(Queue)

    daemon.instance_variable_set(:@worker, worker)
    daemon.instance_variable_set(:@scheduler, scheduler)
    daemon.instance_variable_set(:@server, server)
    daemon.instance_variable_set(:@queue, queue)

    allow(queue).to receive(:pop).with(timeout: 3 * 60 * 60).and_raise(stop_run)

    expect do
      daemon.run
    end.to raise_error(stop_run)

    expect(worker).to have_received(:start).ordered
    expect(scheduler).to have_received(:start).ordered
    expect(server).to have_received(:start).ordered
    expect(daemon.replace_count).to eq(1)
  end
end
