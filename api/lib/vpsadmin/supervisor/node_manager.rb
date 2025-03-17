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
        Node::DnsStatus,
        Node::NetAccounting,
        Node::NetMonitor,
        Node::OomReports,
        Node::PoolStatus,
        Node::Rpc,
        Node::Status,
        Node::StorageStatus,
        Node::VpsEvents,
        Node::VpsMounts,
        Node::VpsOsProcesses,
        Node::VpsOsRelease,
        Node::VpsSshHostKeys,
        Node::VpsStatus
      ].to_h do |klass|
        chan = @connection.create_channel
        chan.prefetch(1)
        klass.setup(chan) if klass.respond_to?(:setup)
        [klass, chan]
      end

      ::Node.includes(:location).where(active: true).each do |node|
        use_klasses =
          if %w[node storage].include?(node.role)
            klasses.reject { |klass, _| klass == Node::DnsStatus }
          elsif node.role == 'dns_server'
            klasses.slice(Node::Rpc, Node::Status, Node::DnsStatus)
          else
            klasses.slice(Node::Rpc, Node::Status)
          end

        use_klasses.each do |klass, chan|
          instance = klass.new(chan, node)
          instance.start
        end
      end
    end
  end
end
