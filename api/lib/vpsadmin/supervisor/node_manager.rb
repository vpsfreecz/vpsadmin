module VpsAdmin::Supervisor
  class NodeManager
    # @param connection [Bunny::Session]
    def self.start(connection)
      m = new(connection)
      m.start
    end

    def initialize(connection)
      @connection = connection
    end

    def start
      klasses = [
        Node::DatasetExpansions,
        Node::NetAccounting,
        Node::NetMonitor,
        Node::OomReports,
        Node::PoolStatus,
        Node::Rpc,
        Node::Status,
        Node::StorageStatus,
        Node::VpsMounts,
        Node::VpsOsProcesses,
        Node::VpsSshHostKeys,
        Node::VpsStatus,
      ].map do |klass|
        chan = @connection.create_channel
        chan.prefetch(1)
        klass.setup(chan) if klass.respond_to?(:setup)
        [klass, chan]
      end

      ::Node
        .includes(:location)
        .where(
          active: true,
          role: %w(node storage),
        )
        .each do |node|
        klasses.each do |klass, chan|
          instance = klass.new(chan, node)
          instance.start
        end
      end
    end
  end
end