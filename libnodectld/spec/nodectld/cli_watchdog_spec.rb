# frozen_string_literal: true

require 'spec_helper'
require 'socket'
require 'timeout'
require_relative '../../../nodectld/lib/nodectld/cli'

RSpec.describe NodeCtld::Cli do
  subject(:cli) { described_class.allocate }

  describe '#run_watchdog' do
    [
      [{ last_transaction_progress_monotonic: 95.0, last_transaction_check_monotonic: 12.0 }, 95.0],
      [{ last_transaction_check_monotonic: 12.0 }, 12.0],
      [{}, nil]
    ].each do |response, expected_check|
      it "uses the available progress timestamp from #{response.inspect}" do
        watchdog_cli = described_class.allocate
        queue = instance_double(OsCtl::Lib::Queue)
        allow(queue).to receive(:pop).and_return(nil, :stop)
        watchdog_cli.instance_variable_set(:@watchdog_queue, queue)
        state = instance_double(NodeCtld::TransactionWatchdog)
        allow(NodeCtld::TransactionWatchdog).to receive(:new).and_return(state)
        allow(state).to receive(:observe).and_return(NodeCtld::TransactionWatchdog::Result.new)
        allow(watchdog_cli).to receive_messages(
          monotonic_now: 100.0,
          get_daemon_response: { status: 'ok', response: }
        )

        watchdog_cli.send(:run_watchdog, 123, daemon_started_at: 1.0)

        expect(state).to have_received(:observe).with(now: 100.0, last_check: expected_check)
      end
    end
  end

  describe '#get_daemon_response' do
    it 'uses one deadline for the greeting and command response' do
      cli_class = Class.new(described_class) do
        attr_reader :deadlines

        def monotonic_now
          100.0
        end

        def remote_receive(_sock, deadline:)
          @deadlines ||= []
          @deadlines << deadline
          @deadlines.length == 1 ? { version: '1.0' } : { status: 'ok', response: {} }
        end
      end
      deadline_cli = cli_class.allocate
      sock = instance_double(UNIXSocket, puts: nil, close: nil)
      allow(UNIXSocket).to receive(:new).and_return(sock)

      expect(deadline_cli.send(:get_daemon_response, :watchdog_status)).to eq(
        status: 'ok',
        response: {}
      )
      expect(deadline_cli.deadlines).to eq([110.0, 110.0])
      expect(sock).to have_received(:puts).with(
        { command: :watchdog_status, params: {} }.to_json
      )
    end
  end

  describe '#remote_receive' do
    it 'reads one JSON response line' do
      reader, writer = Socket.pair(:UNIX, :STREAM, 0)
      writer.write("{\"status\":\"ok\",\"response\":{}}\n")

      deadline = cli.send(:monotonic_now) + 1
      expect(cli.send(:remote_receive, reader, deadline:)).to eq(
        status: 'ok',
        response: {}
      )
    ensure
      reader&.close
      writer&.close
    end

    it 'times out when remote control does not respond' do
      reader, writer = Socket.pair(:UNIX, :STREAM, 0)

      expect do
        cli.send(:remote_receive, reader, deadline: cli.send(:monotonic_now))
      end.to raise_error(Timeout::Error, /remote control timed out/)
    ensure
      reader&.close
      writer&.close
    end
  end
end
