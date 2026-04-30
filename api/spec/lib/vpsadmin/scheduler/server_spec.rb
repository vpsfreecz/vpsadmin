# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'stringio'

RSpec.describe VpsAdmin::Scheduler::Server do
  def build_socket(input)
    Class.new(Struct.new(:input, :output)) do
      def readline = input.readline
      def puts(data) = output.puts(data)
      def close = nil

      def read
        output.rewind
        output.read
      end
    end.new(StringIO.new(input), StringIO.new)
  end

  it 'exposes scheduler, worker and daemon collaborators' do
    scheduler = instance_double(VpsAdmin::Scheduler::CronScheduler)
    worker = instance_double(VpsAdmin::Scheduler::Worker)
    daemon = instance_double(VpsAdmin::Scheduler::Daemon)
    server = described_class.new(daemon, scheduler, worker)

    expect(server.daemon).to eq(daemon)
    expect(server.scheduler).to eq(scheduler)
    expect(server.worker).to eq(worker)
  end

  it 'builds a client for accepted sockets' do
    scheduler = instance_double(VpsAdmin::Scheduler::CronScheduler, size: 0)
    worker = instance_double(VpsAdmin::Scheduler::Worker)
    daemon = instance_double(VpsAdmin::Scheduler::Daemon)
    server = described_class.new(daemon, scheduler, worker)
    request = JSON.dump('command' => 'status', 'arguments' => [])
    sock = build_socket("#{request}\n")

    server.send(:handle_client, sock)

    expect(JSON.parse(sock.read)).to eq(
      'status' => true,
      'response' => { 'task_count' => 0 }
    )
  end

  describe described_class::Client do
    subject(:client) { described_class.new(sock, server_context) }

    let(:cron_task) do
      instance_double(
        VpsAdmin::Scheduler::CronTask,
        export: { id: 7, class_name: 'Task', row_id: 9 }
      )
    end
    let(:server_context) do
      scheduler = instance_double(
        VpsAdmin::Scheduler::CronScheduler,
        size: 1,
        get_tasks: { 7 => cron_task },
        get_task: cron_task
      )
      worker = instance_double(VpsAdmin::Scheduler::Worker, :<< => nil)
      daemon = instance_double(VpsAdmin::Scheduler::Daemon, update: true)

      instance_double(
        VpsAdmin::Scheduler::Server,
        scheduler: scheduler,
        worker: worker,
        daemon: daemon
      )
    end
    let(:sock) { StringIO.new }

    def response
      sock.rewind
      JSON.parse(sock.read)
    end

    it 'returns task count for status' do
      client.run('command' => 'status', 'arguments' => [])

      expect(response).to eq(
        'status' => true,
        'response' => { 'task_count' => 1 }
      )
    end

    it 'returns exported tasks' do
      client.run('command' => 'get-tasks', 'arguments' => [])

      expect(response).to eq(
        'status' => true,
        'response' => {
          'tasks' => [
            { 'id' => 7, 'class_name' => 'Task', 'row_id' => 9 }
          ]
        }
      )
    end

    it 'enqueues a task for manual execution' do
      client.run('command' => 'run-task', 'arguments' => [7])

      expect(server_context.worker).to have_received(:<<).with(cron_task)
      expect(response).to eq('status' => true, 'response' => 'Task executed')
    end

    it 'returns an error when a manual task is missing' do
      allow(server_context.scheduler).to receive(:get_task).with(99).and_return(nil)

      client.run('command' => 'run-task', 'arguments' => [99])

      expect(server_context.worker).not_to have_received(:<<)
      expect(response).to eq('status' => false, 'error' => 'Task 99 not found')
    end

    it 'requests daemon updates' do
      client.run('command' => 'update', 'arguments' => [])

      expect(server_context.daemon).to have_received(:update)
      expect(response).to eq('status' => true, 'response' => 'Done')
    end

    it 'returns syntax errors for invalid JSON' do
      client.parse('{')

      expect(response).to eq('status' => false, 'error' => 'Syntax error')
    end

    it 'returns an error for invalid request shape' do
      client.run('command' => 'status')

      expect(response).to eq('status' => false, 'error' => 'Invalid request')
    end

    it 'returns an error for unknown commands' do
      client.run('command' => 'missing', 'arguments' => [])

      expect(response).to eq('status' => false, 'error' => 'Command "missing" not known')
    end

    it 'ignores EPIPE while sending a response' do
      broken_sock = instance_double(StringIO)
      broken_client = described_class.new(broken_sock, server_context)

      allow(broken_sock).to receive(:puts).and_raise(Errno::EPIPE)

      expect do
        broken_client.run('command' => 'status', 'arguments' => [])
      end.not_to raise_error
    end

    it 'ignores connection resets during communication' do
      broken_sock = instance_double(StringIO)
      broken_client = described_class.new(broken_sock, server_context)

      allow(broken_sock).to receive(:readline).and_raise(Errno::ECONNRESET)

      expect { broken_client.communicate }.not_to raise_error
    end
  end
end
