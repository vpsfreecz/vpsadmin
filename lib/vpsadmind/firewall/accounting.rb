module VpsAdmind::Firewall
  class Accounting
    ROLES = %i(public private)

    attr_reader :fw, *ROLES

    def initialize(fw)
      @fw = fw
      @roles = []
      
      ROLES.each do |r|
        acc = AccountingRole.new(fw, r)
        @roles << acc

        instance_variable_set("@#{r}", acc)
      end
    end

    def init(db, v)
      @roles.each { |r| r.init(db, v) }
    end
  
    def reg_ip(addr, v)
      @roles.each { |r| r.reg_ip(addr, v) }
    end

    def unreg_ip(addr, v)
      @roles.each { |r| r.unreg_ip(addr, v) }
    end
    def update_traffic(db)
      @roles.each { |r| r.update_traffic(db) }
    end

    def cleanup
      @roles.each { |r| r.cleanup }
    end
  end
end
