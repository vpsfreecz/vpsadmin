# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::Supervisor do
  describe '.create_channel' do
    it 'logs the consumer and complete exception chain through Bunny' do
      logger = instance_spy(Logger)
      connection = instance_double(Bunny::Session, logger:)
      channel = instance_double(Bunny::Channel)
      handler = nil

      allow(connection).to receive(:create_channel).and_return(channel)
      allow(channel).to receive(:on_uncaught_exception) { |&block| handler = block }

      expect(described_class.create_channel(connection)).to eq(channel)

      exception = begin
        capture_nested_exception
      rescue StandardError => e
        e
      end
      handler.call(exception, double(to_s: 'queue=node:node1.example:statuses'))

      expect(logger).to have_received(:error) do |message|
        expect(message).to include(
          'Uncaught exception from consumer queue=node:node1.example:statuses',
          'outer failure (RuntimeError)',
          'inner failure (ArgumentError)',
          'capture_nested_exception'
        )
      end
    end
  end

  describe 'channel users' do
    let(:connection) { instance_double(Bunny::Session) }
    let(:channel) { instance_spy(Bunny::Channel) }

    it 'configures channels used by NodeManager' do
      nodes = instance_double(ActiveRecord::Relation)

      allow(described_class).to receive(:create_channel).with(connection).and_return(channel)
      allow(Node).to receive(:includes).with(:location).and_return(nodes)
      allow(nodes).to receive(:where).with(active: true).and_return([])

      VpsAdmin::Supervisor::NodeManager.new(connection).start

      expect(described_class).to have_received(:create_channel).with(connection).at_least(:once)
    end

    it 'configures the console RPC channel' do
      rpc = instance_spy(VpsAdmin::Supervisor::Console::Rpc)

      allow(described_class).to receive(:create_channel).with(connection).and_return(channel)
      allow(VpsAdmin::Supervisor::Console::Rpc).to receive(:new).with(channel).and_return(rpc)

      VpsAdmin::Supervisor::Console::Rpc.start(connection)

      expect(described_class).to have_received(:create_channel).with(connection)
      expect(rpc).to have_received(:start)
    end
  end

  def capture_nested_exception
    raise ArgumentError, 'inner failure'
  rescue ArgumentError
    raise 'outer failure'
  end
end
