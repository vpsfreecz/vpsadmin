module VpsAdmind::Firewall
  class Networks
    include ::Enumerable

    ROLES = %i(public private)
    Network = Struct.new(:version, :addr, :prefix, :role) do
      def to_s
        "#{addr}/#{prefix}"
      end
    end

    def initialize
      @networks = []
    end

    def populate(db)
      @networks.clear unless @networks.empty?

      db.query("
          SELECT ip_version, address, prefix, role
          FROM networks
          WHERE type = 'Network'
      ").each_hash do |row|
        @networks << Network.new(
            row['ip_version'].to_i,
            row['address'],
            row['prefix'].to_i,
            ROLES[ row['role'].to_i ],
        )
      end
    end

    ROLES.each do |r|
      define_method(r) { @networks.select { |n| n.role == r } }
    end

    def each(&block)
      @networks.each(&block)
    end
  end
end
