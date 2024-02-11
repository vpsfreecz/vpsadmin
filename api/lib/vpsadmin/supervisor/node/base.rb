module VpsAdmin::Supervisor
  class Node::Base
    # @return [Bunny::Channel]
    attr_reader :channel

    # @return [::Node]
    attr_reader :node

    # @param channel [Bunny::Channel]
    # @param node [::Node]
    def initialize(channel, node)
      @channel = channel
      @node = node
    end

    protected

    def exchange_name
      "node:#{node.domain_name}"
    end

    def queue_name(name)
      "node:#{node.domain_name}:#{name}"
    end
  end
end
