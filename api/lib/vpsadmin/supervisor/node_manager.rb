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
      ::Node
        .includes(:location)
        .where(
          active: true,
          role: %w(node storage),
        )
        .each do |node|
        chan = @connection.create_channel
        chan.prefetch(1)

        [
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
        ].each do |klass|
          instance = klass.new(chan, node)
          instance.start
        end
      end
    end
  end
end
