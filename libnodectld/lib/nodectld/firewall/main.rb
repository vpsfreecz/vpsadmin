require 'libosctl'
require 'nodectld/db'
require 'nodectld/utils'
require 'nodectld/firewall/ip_map'
require 'nodectld/firewall/networks'
require 'nodectld/firewall/accounting'

module NodeCtld::Firewall
  class Main
    include OsCtl::Lib::Utils::Log
    include NodeCtld::Utils::System
    include NodeCtld::Utils::Iptables

    class << self
      def instance
        return @instance if @instance
        @instance = new
      end

      def get
        instance
      end

      def synchronize(&block)
        instance.synchronize(&block)
      end

      %i(accounting ip_map networks).each do |v|
        define_method(v) { instance.send(v) }
      end
    end

    attr_reader :accounting, :ip_map, :networks

    private
    def initialize
      @mutex = ::Mutex.new
      @ip_map = IpMap.new
      @networks = Networks.new
      @accounting = Accounting.new(self)
    end

    public
    def init(db)
      networks.populate(db)
      ip_map.populate(db)
      ip_map.start

      networks.deploy!

      [4, 6].each do |v|
        ret = iptables(v, {N: 'vpsadmin_main'}, valid_rcs: [1,])

        # Chain already exists, we don't have to continue
        if ret.exitstatus == 1
          log("Skipping init for IPv#{v}, chain vpsadmin_main already exists")
          next
        end

        iptables(v, ['-A', 'FORWARD', '-j', 'vpsadmin_main'])

        accounting.init(db, v)

        # skip local transfers
        iptables(v, [
          '-A', 'vpsadmin_main',
          '-m set', "--match-set vpsadmin_v#{v}_local_addrs src",
          '-m set', "--match-set vpsadmin_v#{v}_local_addrs dst",
          '-j', 'ACCEPT',
        ])

        # pub ip to pub ip -> private traffic
        iptables(v, [
          '-A', 'vpsadmin_main',
          '-m set', "--match-set vpsadmin_v#{v}_networks_public src",
          '-m set', "--match-set vpsadmin_v#{v}_networks_public dst",
          '-j', accounting.private.chain,
        ])

        # pub ip to priv ip -> private traffic
        iptables(v, [
          '-A', 'vpsadmin_main',
          '-m set', "--match-set vpsadmin_v#{v}_networks_public src",
          '-m set', "--match-set vpsadmin_v#{v}_networks_private dst",
          '-j', accounting.private.chain,
        ])

        # priv ip to pub ip -> private traffic
        iptables(v, [
          '-A', 'vpsadmin_main',
          '-m set', "--match-set vpsadmin_v#{v}_networks_private src",
          '-m set', "--match-set vpsadmin_v#{v}_networks_public dst",
          '-j', accounting.private.chain,
        ])

        # priv ip to priv ip -> private traffic
        iptables(v, [
          '-A', 'vpsadmin_main',
          '-m set', "--match-set vpsadmin_v#{v}_networks_private src",
          '-m set', "--match-set vpsadmin_v#{v}_networks_private dst",
          '-j', accounting.private.chain,
        ])

        # everything else is to be considered as public traffic
        iptables(v, ['-A', 'vpsadmin_main', '-j', accounting.public.chain])
      end
    end

    def flush(db = nil)
      created = false

      unless db
        db = Db.new
        created = true
      end

      [4, 6].each do |v|
        iptables(v, ['-D', 'FORWARD', '-j', 'vpsadmin_main'])
        iptables(v, {F: 'vpsadmin_main'})
        iptables(v, {X: 'vpsadmin_main'})
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
