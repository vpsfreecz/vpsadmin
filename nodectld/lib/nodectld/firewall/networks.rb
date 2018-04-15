require 'nodectld/firewall/ip_set'

module NodeCtld::Firewall
  class Networks
    include ::Enumerable

    ROLES = %i(public private)
    Network = Struct.new(:version, :addr, :prefix, :role) do
      def to_s
        "#{addr}/#{prefix}"
      end
    end

    def initialize
      @mutex = ::Mutex.new
      @networks = []
    end

    def populate(db)
      sync do
        @networks.clear unless @networks.empty?

        db.query("
            SELECT ip_version, address, prefix, role
            FROM networks
        ").each do |row|
          @networks << Network.new(
            row['ip_version'].to_i,
            row['address'],
            row['prefix'].to_i,
            ROLES[ row['role'].to_i ],
          )
        end
      end
    end

    ROLES.each do |r|
      define_method(r) { sync { @networks.select { |n| n.role == r } } }
    end

    def each(&block)
      sync { @networks.each(&block) }
    end

    def add!(v, addr, prefix, role)
      sync do
        r = ROLES[role]
        n = Network.new(v, addr, prefix, r)
        @networks << n

        IpSet.append!("vpsadmin_v#{n.version}_networks_#{r}", [n.to_s])
      end
    end

    def remove!(v, addr, prefix, role)
      sync do
        @networks.delete(Network.new(v, addr, prefix, ROLES[role]))
        deploy!(ROLES[role])
      end
    end

    def deploy!(role = nil)
      if role.nil?
        ROLES.each { |r| deploy!(r) }

      else
        [4, 6].each do |v|
          IpSet.create_or_replace!(
            "vpsadmin_v#{v}_networks_#{role}",
            "hash:net family #{v == 4 ? 'inet' : 'inet6'}",
            send(role).select { |n| n.version == v }.map(&:to_s)
          )
        end
      end
    end

    protected
    def sync
      @mutex.synchronize { yield }
    end
  end
end
