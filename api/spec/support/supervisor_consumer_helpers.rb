# frozen_string_literal: true

module SupervisorConsumerHelpers
  FakeDeliveryInfo = Struct.new(:delivery_tag)

  class FakeSupervisorChannel
    attr_reader :queues, :exchange_names, :acked_tags

    def initialize
      @queues = {}
      @exchange_names = []
      @acked_tags = []
    end

    def direct(name)
      @exchange_names << name
      Object.new
    end

    def queue(name, **opts)
      @queues[name] = FakeSupervisorQueue.new(name, opts)
    end

    def ack(tag)
      @acked_tags << tag
    end
  end

  class FakeSupervisorQueue
    attr_reader :name, :opts, :routing_key, :subscribe_args, :subscribe_kwargs

    def initialize(name, opts)
      @name = name
      @opts = opts
    end

    def bind(_exchange, routing_key:)
      @routing_key = routing_key
      self
    end

    def subscribe(*args, **kwargs, &block)
      @subscribe_args = args
      @subscribe_kwargs = kwargs
      @subscriber = block
      self
    end

    def publish(payload)
      @subscriber.call(FakeDeliveryInfo.new(1), nil, payload)
    end
  end
end

RSpec.configure do |config|
  config.include SupervisorConsumerHelpers
end
