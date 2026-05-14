# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/utils/subprocess'

RSpec.describe NodeCtld::Utils::Subprocess do
  let(:daemon) { instance_double(NodeCtldSpec::FakeDaemon) }
  let(:command) { instance_double(NodeCtld::Command, chain_id: 10) }

  let(:worker_class) do
    Class.new do
      include NodeCtld::Utils::Subprocess

      def initialize(command, daemon)
        @command = command
        @daemon = daemon
      end

      def log(*); end
    end
  end

  it 'kills only subprocesses registered for the current chain' do
    worker = worker_class.new(command, daemon)

    allow(daemon).to receive(:chain_blockers).and_yield(
      10 => [111, 112],
      20 => [221]
    )
    allow(Process).to receive(:kill)

    worker.killall_subprocesses

    expect(Process).to have_received(:kill).with('TERM', -111)
    expect(Process).to have_received(:kill).with('TERM', -112)
    expect(Process).not_to have_received(:kill).with('TERM', -221)
  end

  it 'kills all subprocesses when no transaction command is present' do
    worker = worker_class.new(nil, daemon)

    allow(daemon).to receive(:chain_blockers).and_yield(
      10 => [111],
      20 => [221]
    )
    allow(Process).to receive(:kill)

    worker.killall_subprocesses

    expect(Process).to have_received(:kill).with('TERM', -111)
    expect(Process).to have_received(:kill).with('TERM', -221)
  end
end
