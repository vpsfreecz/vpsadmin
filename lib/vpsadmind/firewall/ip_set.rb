module VpsAdmind::Firewall
  class IpSet
    include VpsAdmind::Utils::Log
    include VpsAdmind::Utils::System
    include VpsAdmind::Utils::Iptables

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

    def initialize(name, type)
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
      tmp = "#{@name}_new"
      do_create(tmp)
      ipset(:swap, tmp, @name)
      ipset(:destroy, tmp)
    end

    def create_or_replace!
      create!

    rescue VpsAdmind::CommandFailed => e
      raise e if e.rc != 1 || e.output !~ /set with the same name already exists/

      replace!
    end

    def test!(ip)
      ipset(:test, @name, ip)
      true

    rescue VpsAdmind::CommandFailed
      false
    end

    protected
    def do_create(name)
      ipset(:create, name, @type)
      @ips.each { |ip| puts "\nIPSET ADD #{ip}\n" ; ipset(:add, name, ip) }
    end
  end
end
