# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::Scheduler::Worker do
  let(:worker) { worker_class.new }
  let(:worker_class) do
    Class.new(described_class) do
      attr_reader :messages, :warnings

      def initialize
        super
        @messages = []
        @warnings = []
      end

      def puts(message)
        @messages << message
      end

      def warn(message)
        @warnings << message
      end
    end
  end
  let(:cron_task) do
    VpsAdmin::Scheduler::CronTask.new(
      id: 1,
      class_name: fake_model_name,
      row_id: 42
    )
  end
  let(:fake_model_name) { 'SchedulerWorkerSpecTask' }

  before do
    stub_const(fake_model_name, Class.new)
    fake_model = Object.const_get(fake_model_name)

    fake_model.define_singleton_method(:primary_key) { 'id' }
    allow(ActiveRecord::Base.connection_pool).to receive(:with_connection).and_yield
  end

  it 'looks up the task by class name and primary key' do
    fake_model = Object.const_get(fake_model_name)
    task = instance_double(fake_model, id: 42, execute: true)

    allow(fake_model).to receive(:find_by).with('id' => 42).and_return(task)

    worker.send(:run_task, cron_task)

    expect(fake_model).to have_received(:find_by).with('id' => 42)
  end

  it 'executes the resolved row' do
    fake_model = Object.const_get(fake_model_name)
    task = instance_double(fake_model, id: 42, execute: true)

    allow(fake_model).to receive(:find_by).and_return(task)

    worker.send(:run_task, cron_task)

    expect(task).to have_received(:execute)
  end

  it 'warns and does not raise when the row is missing' do
    fake_model = Object.const_get(fake_model_name)

    allow(fake_model).to receive(:find_by).and_return(nil)

    expect { worker.send(:run_task, cron_task) }.not_to raise_error
    expect(worker.warnings).to include("Action #{fake_model_name} = 42 not found")
  end

  it 'rescues task exceptions and warns' do
    fake_model = Object.const_get(fake_model_name)
    task = instance_double(fake_model, id: 42)
    error = RuntimeError.new('boom')

    allow(fake_model).to receive(:find_by).and_return(task)
    allow(task).to receive(:execute).and_raise(error)

    expect { worker.send(:run_task, cron_task) }.not_to raise_error
    expect(worker.warnings).to include(
      'Repeatable task #42 failed!',
      error.inspect,
      error.backtrace
    )
  end
end
