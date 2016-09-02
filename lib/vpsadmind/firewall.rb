module VpsAdmind
  class Firewall
    include Utils::Log
    include Utils::System
    include Utils::Iptables

    def self.instance
      return @instance if @instance
      @instance = new
    end

    def self.get
      instance
    end

    def self.accounting
      instance.accounting
    end
    
    def self.ip_map
      instance.ip_map
    end

    def self.synchronize(&block)
      instance.synchronize(&block)
    end

    attr_reader :accounting, :ip_map

    private
    def initialize
      @mutex = ::Mutex.new
      @ip_map = IpMap.new
      @accounting = Accounting.new(self)
    end

    public
    def init(db)
      ip_map.populate(db)
      accounting.init(db)
    end

    def flush(db = nil)
      created = false

      unless db
        db = Db.new
        created = true
      end

      accounting.update_traffic(db)
      accounting.cleanup

      db.close if created
    end

    def reinit(db = nil)
      created = false

      unless db
        db = Db.new
        created = true
      end

      accounting.update_traffic(db)
      cleanup
      r = init(db)

      db.close if created
      r
    end

    def cleanup
      accounting.cleanup
    end
    
    def synchronize
      if @mutex.owned?
        yield(self)

      else
        @mutex.synchronize { yield(self) }
      end
    end
  end
end
