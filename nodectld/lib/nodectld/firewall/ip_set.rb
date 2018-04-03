module NodeCtld::Firewall
  class IpSet
    include OsCtl::Lib::Utils::Log
    include NodeCtld::Utils::System
    include NodeCtld::Utils::Iptables

    def self.create!(name, type, ips)
      set = new(name, type)
      set.concat(ips)
      set.create!
    end

    def self.replace!(name, type, ips)
      set = new(name, type)
      set.concat(ips)
      set.replace!
    end

    def self.create_or_replace!(name, type, ips)
      set = new(name, type)
      set.concat(ips)
      set.create_or_replace!
    end

    def self.append!(name, ips)
      set = new(name)
      set.concat(ips)
      set.append!
    end

    def initialize(name, type = nil)
      @name = name
      @type = type
      @ips = []
    end

    def <<(ip)
      @ips << ip
    end

    def concat(ips)
      @ips.concat(ips)
    end

    def create!
      do_create(@name)
    end

    def replace!
      tmp = "#{@name}.n"
      do_create(tmp)
      ipset(:swap, tmp, @name)
      ipset(:destroy, tmp)
    end

    def create_or_replace!
      create!

    rescue NodeCtld::SystemCommandFailed => e
      raise e if e.rc != 1 || e.output !~ /set with the same name already exists/

      replace!
    end

    def append!
      @ips.each { |ip| ipset(:add, @name, ip) }
    end

    def test!(ip)
      ipset(:test, @name, ip)
      true

    rescue NodeCtld::SystemCommandFailed
      false
    end

    protected
    def do_create(name)
      ipset(:create, name, @type)
      @ips.each { |ip| ipset(:add, name, ip) }
    end
  end
end
